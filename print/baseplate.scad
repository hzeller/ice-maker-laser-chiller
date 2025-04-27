$fn=50;
e=0.01;

thick=3;

module rounded_rectangle(c=[25.4, 12, 1], r=2.5) {
  translate([0, c[1]/2, c[2]/2]) hull() {
    translate([r,     c[1]/2-r, -c[2]/2]) cylinder(r=r, h=c[2]);
    translate([r,    -c[1]/2+r, -c[2]/2]) cylinder(r=r, h=c[2]);
    translate([c[0]-r, -c[1]/2+r, -c[2]/2]) cylinder(r=r, h=c[2]);
    translate([c[0]-r,  c[1]/2-r, -c[2]/2]) cylinder(r=r, h=c[2]);
  }
}

module hexagon_row(n=10, d=1, cell_dia=10, h=10) {
  w=cell_dia*sqrt(3)/2 + d;
  for (i = [0:1:n]) {
    translate([i*w, 0, 0]) rotate([0, 0, 30]) cylinder(r=cell_dia/2, h=h, $fn=6);
  }
}

module hexagon_plane(n=10, d=1, cell_dia=10, h=10) {
  w=cell_dia*sqrt(3)/2 + d;
  for (i = [0:2:n]) {
    translate([0, i*w*sqrt(3)/2, 0])hexagon_row(n, d, cell_dia, h);
    translate([w/2, (i+1)*w*sqrt(3)/2, 0]) hexagon_row(n, d, cell_dia, h);
  }
}


module top(w=100, h=100, t=1, cell_dia=10, d=0.7, frame=1, r=4) {
  difference() {
    rounded_rectangle ([w, h, t], r=r);
    intersection() {
      translate([0, 0, -e]) hexagon_plane(n=2*w/cell_dia, cell_dia=cell_dia, d=d, h=t+2*e);
      translate([frame, frame, -e]) rounded_rectangle ([w-2*frame, h-2*frame, 100], r=r-frame);
    }
  }
}


module hole(t=thick, punch=false) {
  if (punch) {
    translate([0, 0, -1]) cylinder(r=4.2/2, h=10);
  } else {
    cylinder(r=4, h=t);
  }
}

module project_area(w=30, h=15, t=1, frame=2, punch=false) {
  if (punch) {
    translate([0, 0, -e]) {
      cube([w, h, t+2*e]);
      translate([0, 0, 0]) cylinder(r=0.5, h=t+2*e);
      translate([w, 0, 0]) cylinder(r=0.5, h=t+2*e);
      translate([0, h, 0]) cylinder(r=0.5, h=t+2*e);
      translate([w, h, 0]) cylinder(r=0.5, h=t+2*e);
    }
  } else {
    difference() {
      translate([-frame, -frame, 0]) rounded_rectangle([w+2*frame, h+2*frame, t]);
      project_area(w=w, h=h, t=t, frame=frame, punch=true);
    }
  }
}

intersection() {
difference() {
  union() {
    top(w=130, h=61, t=thick);
    translate([2, 8, 0]) project_area(w=73.3, h=50.2, t=thick+5);
    translate([78, 7, 0]) project_area(h=51.2, w=26.2, t=thick);
    translate([110, 7, 0]) project_area(h=43.2, w=17.5, t=thick+4);

    translate([8, 4, 0]) hole(t=thick+5);
    translate([8+114.5, 4, 0]) hole();
    translate([8, 4+52, 0]) hole();
    translate([8+114.5, 4+52, 0]) hole(t=thick+4);

  }
  translate([2, 8, thick]) project_area(w=73.3, h=50.2, t=2*thick, punch=true);
  translate([78, 7, 0]) project_area(h=51.2, w=26.2, t=2*thick, punch=true);
  translate([110, 7, thick]) project_area(h=43.2, w=17.5, t=2*thick, punch=true);

  translate([8, 4, 0]) hole(punch=true);
  translate([8+114.5, 4, 0]) hole(punch=true);
  translate([8, 4+52, 0]) hole(punch=true);
  translate([8+114.5, 4+52, 0]) hole(punch=true);
 }


 rounded_rectangle([130, 61, 30]);
}
//rounded_rectangle([50, 50, 10]);
//color("green") cube([50, 50, 12]);
