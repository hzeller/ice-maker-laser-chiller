e=0.01;
$fn=60;

mount_height=25;

module cavity() {
  translate([0, 40, 0]) cylinder(r=13, h=30);
  translate([-50, 0, 0]) cube([50, 120, 30]);


  translate([0, 0, -50]) cube([70, 120, 50]);
  rs=53+12.5;
  hull() {
    translate([rs, 0, 0]) cube([e, 120, e]);
    translate([rs+30, 0, 30]) cube([e, 120, e]);
    translate([rs+30, 0, -50]) cube([e, 120, e]);
    translate([rs, 0, -50]) cube([e, 120, e]);
  }
}

module pump() {
  hole_x=60;
  hole_y=51;
  color("green") cube([73, 77, 40]);
  translate([73/2-hole_x/2, 77/2-hole_y/2, -15]) cylinder(r=4/2, h=16);
  translate([73/2+hole_x/2, 77/2-hole_y/2, -15]) cylinder(r=4/2, h=16);
  translate([73/2-hole_x/2, 77/2+hole_y/2, -15]) cylinder(r=4/2, h=16);
  translate([73/2+hole_x/2, 77/2+hole_y/2, -15]) cylinder(r=4/2, h=16);
}

module podest() {
  difference() {
    cube([90, 80, mount_height]);
    translate([17, -1, 0]) cube([45, 81, mount_height-5]);
  }
}

if (false) difference() {
  podest();
  color("blue") translate([0, -(40-28), 0]) cavity();
  translate([14, 1, mount_height]) pump();
}

//color("blue") translate([0, -(40-28), 0]) cavity();

module retainer() {
  hull() {
    sphere(r=5/2);
    translate([0, 0, -3]) sphere(r=3/2);
    translate([0, 0, +3]) sphere(r=3/2);
  }
  cylinder(r=3.5/2, h=8);
  translate([0, 0, 8]) cylinder(r=8/2, h=1);
}

translate([ 10,  10, 0]) retainer();
translate([ 10, -10, 0]) retainer();
translate([-10, -10, 0]) retainer();
translate([-10,  10, 0]) retainer();
