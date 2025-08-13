// A simple case for the MiSTeryNano Lite  (https://github.com/harbaum/MiSTeryNano)

// Original author: Oliver Jaksch
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// PCB size: 23.2x54.2

// Bottom
difference() {
    $fn=150;
    minkowski() {
        cube([24.2, 55.4, 13.3], true);
        cylinder(0.2, 1.5);
    }
    translate ([0, 0, 1.35]) cube([23.4, 54.4, 12], true);

    // Cutout RPi USB-C
    translate ([0, 28.1, 3.3]) cube([11, 3, 7.5], true);
    // Cutout RPi USB-A
    translate ([0, -28.1, 6]) cube([14.5, 3, 11.3], true);

    // LEDs
    translate ([ 0, -25.2, -5.5]) cube([2, 4, 3], true);  // K
    translate ([ 4, -25.2, -5.5]) cube([2, 4, 3], true);  // J
    translate ([-4, -25.2, -5.5]) cube([2, 4, 3], true);  // M
}

// Support Sockets
translate ([0, 10, -3.15]) cube([15, 20, 3], true);
translate ([0, -14, -3.15]) cube([15, 2, 3], true);

// Extra Frame for Bottom
difference() {
   $fn=150;
   minkowski() {
        translate ([0, 0, -4.2]) cube([28.0, 59.2, 5], true);
        cylinder(0.2, 1.5);
    }
    minkowski() {
        translate ([0, 0, -4.2]) cube([24.2, 55.4, 5.5], true);
        cylinder(0.2, 1.5);
    }
}
