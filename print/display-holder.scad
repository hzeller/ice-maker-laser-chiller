$fn=64;
e=0.01;
dw=36;
dh=34.5;
box_draft_angle=2;

module rounded_corner_box(coords=[10,10,10], r=1) {
  hull() {
    translate([0+r, 0+r, 0]) cylinder(r=r, h=coords[2]);
    translate([coords[0]-r, 0+r, 0]) cylinder(r=r, h=coords[2]);
    translate([coords[0]-r, coords[1]-r, 0]) cylinder(r=r, h=coords[2]);
    translate([0+r, coords[1]-r, 0]) cylinder(r=r, h=coords[2]);
  }
}

difference() {
  union() {
    translate([-(dw+2)/2, 0, 0]) cube([dw+2,dh+2,5]);
    translate([-60/2, 0, 0]) cube([60, 38, 1]);
  }
  translate([-dw/2, 1, 1]) cube([dw,dh,5]);
  translate([-(dw-3)/2, 7+3/2, -e]) color("blue") rounded_corner_box([dw-3, 19-3, 10], r=2);

  translate([0, 0, -3])
  linear_extrude(height=10)
    polygon(points=[ [-dw/2+2, 38], [-60/2, 38], [-60/2, 30] ]);
}

rotate([box_draft_angle,0,0])
translate([-55/2+11, 0, 0]) cube([55-11-6.5, 1, 30]);
