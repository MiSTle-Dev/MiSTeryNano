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
    translate ([-10.2, -26.0, 0]) rotate([-45, 90, 0]) cube([5, 6.5, 2], true);
    translate ([-7.3, -23.1, 0]) rotate([-45, 90, 0]) cube([5, 15, 2], true);
    translate ([-4.5, -20, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-4.5, -14, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-4.5, -8, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-4.5, -2, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-4.5, 4, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-4.5, 10, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-4.5, 16, 0]) rotate([-45, 90, 0]) cube([5, 23, 2], true);
    translate ([-3.5, 21, 0]) rotate([-45, 90, 0]) cube([5, 20, 2], true);
    translate ([-0.5, 24, 0]) rotate([-45, 90, 0]) cube([5, 12, 2], true);
}
