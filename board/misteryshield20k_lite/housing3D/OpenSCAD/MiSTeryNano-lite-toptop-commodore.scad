// A simple case for the MiSTeryNano Lite  (https://github.com/harbaum/MiSTeryNano)

// Original author: Oliver Jaksch
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// Top for the Top :)
difference() {
    $fn=150;
    minkowski() {
        cube([28.17, 59.27, 4], true);
        cylinder(0.2, 1.5);
    }

    // Plate
    translate ([11.6, 0, 2.4]) rotate([0, 20, 0]) cube([10, 62.5, 4], true);

    // Vents
    for (step =[-12:4:0]) translate ([step, 0, 0]) cube([2, 55, 5], true);
}
translate ([-6, 10, -0.5]) cube([15, 2, 3], true);
translate ([-6, -10, -0.5]) cube([15, 2, 3], true);