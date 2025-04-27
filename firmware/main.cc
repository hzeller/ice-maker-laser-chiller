// -*- mode: c++; c-basic-offset: 2; indent-tabs-mode: nil; -*-
//
// Copyright (C) 2021 Henner Zeller <h.zeller@acm.org>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#include <avr/interrupt.h>
#include <avr/io.h>
#include <avr/wdt.h>
#include <util/delay.h>

#include <math.h>

#include "i2c-master.h"
#include "sh1106-display.h"
#include "strfmt.h"

#include "font-bignumber.h" // generated from *.chars
#include "font-smalltext.h"

#include "ds18b20/ds18b20.h"

// Scaling temperature and volume to have fixed-point decimal digits.
using temp_tens_t = int32_t; // Celsius * 10 (10th degree resolution)
constexpr temp_tens_t operator"" _C(long double x) { return roundf(10 * x); }

using deciliter_t = int16_t; // Deciliter (100ml)
constexpr deciliter_t operator"" _L(long double x) { return roundf(10 * x); }

/**
 ** Configuration
 **/

/*
 * Cooling needs
 */
// A laser has about 10% efficiency. So a 40W laser needs about 400W cooling.
inline constexpr uint16_t kLaserRequiredCoolingWatt = 400;

// Max acceptable rise in temperature of water while flowing through tube
inline constexpr temp_tens_t kMaxLaserWaterTemperatureRise = 2.0_C;

// Heat capacity of coolant. Water is 4.19J/gK, but will be different if used
// with antifreeze.
inline constexpr float kHeatCapacityWater = 4190.0 / (1.0_L * 1.0_C);

// Minimum flow needed to keep temp rise below threshold given the input heat.
inline constexpr deciliter_t kMinLiterPerMinute =
    60.0 * kLaserRequiredCoolingWatt /
    (kMaxLaserWaterTemperatureRise * kHeatCapacityWater);
inline constexpr deciliter_t kClearFlowAlaram = kMinLiterPerMinute + 0.5L;

// Flow below this we consider a leak, which switches off pump and wait for
// power cycle.
inline constexpr deciliter_t kLeakThreshold = kMinLiterPerMinute / 2;

/*
 * Cutoff points for thermostat. No need for UI, just using fixed values.
 */

// Bang Bang control. Not too cool to avoid potential dew issues.
inline constexpr temp_tens_t kControlLowTemp = 16.0_C;
inline constexpr temp_tens_t kControlHighTemp = kControlLowTemp + 2.0_C;

// Alarm hysteresis. Above range of thermostat, but still keeping
// the laser safe. Alarm is cleared once we're close to regulation range.
inline constexpr temp_tens_t kAlarmTemp = 25.0_C;
inline constexpr temp_tens_t kAlarmClearTemp = kControlHighTemp + 2.0_C;

static_assert(kAlarmClearTemp < kAlarmTemp);

/*
 * Timings
 */
inline constexpr uint16_t kAcquisitionTimeSlotMs = 500;
inline constexpr uint8_t kFanPumpDelay = 120; // running longer after cool off
inline constexpr uint8_t kStartupFlowTimeSlots = 16;  // consider stable after

/*
 * IO-Pins
 */

// Outputs all on port D. PD2 is interrupt (INT0) for flow meter.
// Let's start using the pins above: 4..7
#define OUTPUT_DDR DDRD
#define OUTPUT_PORT PORTD
inline constexpr uint8_t OUT_ALARM = (1 << 4);
inline constexpr uint8_t OUT_INTERNAL_PUMP = (1 << 5);
inline constexpr uint8_t OUT_WATER_OFF = (1 << 6);
inline constexpr uint8_t OUT_COMPRESSOR = (1 << 7);

// Inputs. We sample zero crossing for less noisy relay switching.
// If no zero crossing is used (e.g. when using an SSR), comment out
// the ZERO_CROSSING_INPUT define.
#define ZERO_CROSSING_INPUT PIND
#define ZERO_CROSSING_BIT (1 << 3)

// The mechanical relay has a reaction time, so even if we switch at zero
// crossing, the actual switching will happen well into the next sine-wave.
// So add a delay that the actual switch time coincides with the next
// zero crossing. Needs to be determined emperically.
inline constexpr uint16_t RELAY_DELAY_MICROSECOND = 2800;

/*
 * Temperature sensor
 * One-wire temperature probe on PORTB/PINB
 */
inline constexpr uint8_t DS18B20_WIRE = (1 << 0);
inline constexpr temp_tens_t kErrorTemp = -99.9_C;

/*
 * Flow sensor (connected to INT0)
 * Characteristic of flow meter. See datasheet.
 */
inline constexpr float kFlowFrquencyForLpMin = 23;

struct SensorData {
  temp_tens_t temp;
  deciliter_t water_flow_per_minute;
};

struct ControlOutput {
  bool cooling_on = false;  // Switch on compressor
  uint8_t pump_fan = 0; // Pump and fan when > 0. Stays on longer after cooling.

  bool alarm_temp = true; // Alarm: temperature might compromise tube lifetime
  bool alarm_flow = true; // Alarm: flowrate through tube not sufficient.

  // Countdown until we consider flow solid.
  uint8_t flow_in_startup = kStartupFlowTimeSlots;
  bool alarm_extreme_flow_loss = false;  // Broken pipe ?
};

static bool StartTempSample() {
  return ds18b20convert(&PORTB, &DDRB, &PINB, DS18B20_WIRE, nullptr) == 0;
}
static temp_tens_t ReadTemp() {
  int16_t result = 0;
  if (ds18b20read(&PORTB, &DDRB, &PINB, DS18B20_WIRE, nullptr, &result) != 0) {
    return kErrorTemp;
  }
  return (temp_tens_t)result * 100 / 160;
}

static uint16_t sFlowPulses = 0;
static void StartFlowSample() {
  cli();
  // We're connected to INT0
  EICRA |= (1 << ISC01) | (1 << ISC00); // Positive edge; datasheet 13.2.1
  EIMSK |= 1;                           // INT0 enable
  sFlowPulses = 0;
  sei();
}

ISR(INT0_vect) { ++sFlowPulses; }

static deciliter_t ReadFlow(uint16_t acquisition_ms) {
  static constexpr float kPulsePerLiter = kFlowFrquencyForLpMin * 60 / 1.0_L;
  static constexpr float kMsPerMin = 60000;
  cli();
  return (sFlowPulses / kPulsePerLiter) / (acquisition_ms / kMsPerMin);
}

static void ReadSensors(SensorData *data) {
  // The sensors need some time to sample betwen starting and reading

  const bool temp_started = StartTempSample();
  StartFlowSample();

  _delay_ms(kAcquisitionTimeSlotMs);

  data->water_flow_per_minute = ReadFlow(kAcquisitionTimeSlotMs);
  data->temp = temp_started ? ReadTemp() : kErrorTemp;
}

static void ModifyControlOutput(const SensorData &data, ControlOutput *out) {
  static uint8_t broken_temp_reading_count = 0;
  if (data.temp != kErrorTemp) {
    // Both of these outputs are based on temperature with hysteresis
    out->alarm_temp = out->alarm_temp //
                          ? data.temp > kAlarmClearTemp
                          : data.temp > kAlarmTemp;
    out->cooling_on = out->cooling_on //
                          ? data.temp > kControlLowTemp
                          : data.temp > kControlHighTemp;
    broken_temp_reading_count = 0;
  } else {
    ++broken_temp_reading_count; // Should never happen but be safe if it does
    out->alarm_temp |= (broken_temp_reading_count >= 2);
  }

  // The minimum flow we need to meet laser temperature rise constraints.
  // Alarm with hysteresis: requires flow to recover enough to clear alarm.
  out->alarm_flow = out->alarm_flow
    ? data.water_flow_per_minute < kClearFlowAlaram
    : data.water_flow_per_minute < kMinLiterPerMinute;

  // We are in startup until initial flow reached capacity and alarm cleared
  // for a while. Once startup done, we are then ready to discover leaks.
  if (out->flow_in_startup) {
    if (out->alarm_flow) {
      out->flow_in_startup = kStartupFlowTimeSlots;
    } else {
      --out->flow_in_startup;
    }
  }

  // If we go into a sudden loss of water flow after a stable flow was
  // established already, consider this a leak (such as a dislodged hose),
  // that needs to be contained. Switch off water pump to avoid a mess.
  if (!out->flow_in_startup && data.water_flow_per_minute < kLeakThreshold) {
    out->alarm_extreme_flow_loss = true;  // Can only be reset on power cycle
  }

  // If alarm due to water leak and thus water pump to laser is off,
  // also stop chiller independent of temperature, as there is no point.
  if (out->alarm_extreme_flow_loss) {
    out->cooling_on = false;
  }

  // Internal water pump and fan are off a bit delayed after cooling stops.
  if (out->cooling_on) {
    out->pump_fan = kFanPumpDelay;
  } else if (out->pump_fan > 0) {
    --out->pump_fan;
  }
}

static void Display(SH1106Display *display, //
                    const SensorData &values, const ControlOutput &control) {
  static uint8_t activity_counter = 0;
  uint8_t x;
  display->Print(font_bignumber, 0, 0, strfmt(values.temp, 1, 4),
                 control.alarm_temp);
  display->Print(font_bignumber, 80, 0, "°C", control.alarm_temp);
  x = display->Print(font_smalltext, 0, 32,
                     strfmt(values.water_flow_per_minute, 1, 3, '0'),
                     control.alarm_flow);
  x = display->Print(font_smalltext, x, 32, " l/min", control.alarm_flow);
  x = display->Print(font_smalltext, x, 32, "(", false);
  x = display->Print(font_smalltext, x, 32, strfmt(kMinLiterPerMinute, 1, 3),
                     false);
  display->Print(font_smalltext, x, 32, ")", false);

  x = display->Print(font_smalltext, 56, 48, "cool ");
  display->Print(font_smalltext, x, 48, control.cooling_on ?  " on" : "off",
                     control.cooling_on);

  activity_counter++;
  const bool blink = (activity_counter % 2 == 0);
  if (control.alarm_extreme_flow_loss) {
    display->Print(font_smalltext, 0, 48, "Leak!", blink);
  } else {
    // Indicate that we're active; a walking dot in the corner at startup,
    // water 'flow' ≈≈ after steady flow established. Blinking on alarm.
    const char *activity_string = control.flow_in_startup ? ".   " : "≈   ";
    display->Print(font_smalltext, //
                   (activity_counter % 4) * 6, 48, activity_string);
  }
}

// Wait for AC mains zero crossing to switch relays with minimal EMI
static void WaitZeroCrossing() {
#ifdef ZERO_CROSSING_INPUT
  while ((ZERO_CROSSING_INPUT & ZERO_CROSSING_BIT) != 0) {
    // Wait until we hit negative if not already
  }
  while ((ZERO_CROSSING_INPUT & ZERO_CROSSING_BIT) == 0) {
    // Wait for positive edge.
  }
  _delay_us(RELAY_DELAY_MICROSECOND);  // Accomodate mechanical relay delay
#endif
}

static void SetActuators(const ControlOutput &control) {
  uint8_t out = 0;
  out |= (control.alarm_flow || control.alarm_temp ||
          control.alarm_extreme_flow_loss) ? OUT_ALARM : 0;
  out |= control.pump_fan ? OUT_INTERNAL_PUMP : 0;
  out |= control.cooling_on ? OUT_COMPRESSOR : 0;
  out |= control.alarm_extreme_flow_loss ? OUT_WATER_OFF : 0;
  WaitZeroCrossing();
  OUTPUT_PORT = out;
}

int main() {
  wdt_reset();
  wdt_disable();

  I2CMaster::Init();
  I2CMaster::Enable(true);
  OUTPUT_DDR |= OUT_ALARM | OUT_COMPRESSOR | OUT_INTERNAL_PUMP | OUT_WATER_OFF;

  SH1106Display display;
  display.ClearScreen();
  display.Print(font_smalltext, 10, 16, "Starting...");

  SensorData values;
  ControlOutput control;

  ReadSensors(&values);  // Dummy read, initialize all the things.
  display.ClearScreen();

  wdt_enable(WDTO_4S);  // If for whatever reason things hang > 4s: Reset.

  for (;;) {
    ReadSensors(&values);
    ModifyControlOutput(values, &control);
    SetActuators(control);
    Display(&display, values, control);
    wdt_reset();
  }
}
