include <threads.scad>

$fn=120;
e=0.01;

hose_dia=13;
hose_wall=1;

clearance=0.3;
screw_diameter=60;
screw_pitch=2;
screw_len=16;  // should be 20
screw_wall=3;
flange=10;
flange_dia=screw_diameter + 2*flange;
top_thick=4;  // should be 4-5
emboss=0.8;

module InOut(scale=0.32) {
     scale([scale, scale, 1]) linear_extrude(height=10) scale([1, -1, 1]) translate([-65, -50, 0]) import(file="InNOut.dxf", convexity=10);
}

module fasten_thread(height=screw_len) {
  render() difference() {
    ScrewThread(outer_diam=screw_diameter, height=height, pitch=screw_pitch);
    translate([0, 0, -e]) cylinder(r=screw_diameter/2 - screw_wall, h=height+2*e);
  }
}

module nut(height=screw_len-2, wall=2) {
  difference() {
    ScrewHole(outer_diam=screw_diameter, height=height, pitch=screw_pitch) {
      cylinder(r=screw_diameter/2 + 4, h=height, $fn=12);
      cylinder(r=flange_dia/2, h=2);
    }
    translate([0, 0, -e]) cylinder(r1=screw_diameter/2+1, r2=screw_diameter/2-1, h=2);
  }
}

module meter_punch() {
  rotate([-90, 0, 0]) translate([-9, -15, -16.5]) {
    //cylinder(r=16/2, h=20);
    //translate([0, 0, 1.2]) cylinder(r=30/2, h=18);
    cylinder(r=35.0/2, h=16.5);
    cylinder(r1=30.5/2, r2=29.5/2, h=27);
    bolt_h=20;
    bolt_r=7.2/2;
    dx=27.68;
    dy=24.85;
    translate([-dx/2, -dy/2, -2]) cylinder(r=bolt_r, h=bolt_h);
    translate([-dx/2, +dy/2, -2]) cylinder(r=bolt_r, h=bolt_h);
    translate([+dx/2, -dy/2, -2]) cylinder(r=bolt_r, h=bolt_h);
    translate([+dx/2, +dy/2, -2]) cylinder(r=bolt_r, h=bolt_h);

    translate([0, (35.5/2-10/2-0.5), 0]) cube([2, 10, 1], center=true);
    translate([9, 0, 16.5]) rotate([90, 0, 0]) translate([0, 0, -40]) cylinder(r=16.5/2, h=60);
  }
}

module top() {
  hose_offset=(screw_diameter-hose_dia)/2-hose_wall-screw_wall+1;
  pipe_len=screw_len + top_thick;
  difference() {
    union() {
      cylinder(r1=flange_dia/2-top_thick/2, r2=flange_dia/2, h=top_thick-1);
      translate([0, 0, top_thick-1]) cylinder(r=flange_dia/2, h=1);
      translate([-hose_offset, 0, 0]) cylinder(r=hose_dia/2+hose_wall, h=pipe_len);
      translate([0, 0, top_thick]) linear_extrude(height=1.0) color("gray") lock_ring(false);
    }
    translate([2, -19, emboss]) scale([-1, 1, -1]) color("gray") InOut();
    translate([-12, -22, top_thick-emboss]) linear_extrude(height=1) text("HZ 2023", size=5);
    translate([-hose_offset, 0, -e]) cylinder(r=hose_dia/2, h=pipe_len+2*e);
    translate([-hose_offset, 0, -e]) cylinder(r=hose_dia/2, h=pipe_len+2*e);

    translate([13, 8, 3.8]) rotate([0, 0, 10]) #meter_punch();
  }
}

module assembly() {
  if (true) intersection() {
      union() {
	render() translate([0, 0, top_thick-e]) fasten_thread();
	top();
      }
      //cylinder(r=screw_diameter/2+2, h=50);
      //translate([6, 0, 0]) cylinder(r=42/2, h=5);
    }
}

// is_cut=true if used for cutting through acrylic top.
module lock_ring(is_cut=true, extra=0) {
  difference() {
    union() {
      if (is_cut) circle(r=screw_diameter/2+extra);
      for (a = [90:180:360]) {
	rotate([0, 0, a+90]) translate([screw_diameter/2, 0, 0]) circle(r=flange/2+extra);
      }
    }
    if (!is_cut) circle(r=screw_diameter/2 - screw_wall);
  }
}

//assembly();
//render()
if (true) difference() {
  assembly();
  //translate([0, 0, -10]) cube([100,100,100]);
}

if (false) difference() {
  translate([0, 0, 2*top_thick]) color("red") nut(); // just for visuals
  translate([0, 0, -10]) cube([100,100,100]);
}

//meter_punch();

//nut();
//meter_punch();
//need notch
//lock_ring(is_cut=true, extra=1.5);
