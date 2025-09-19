// A simple case for the MiSTeryNano Lite  (https://github.com/harbaum/MiSTeryNano)

// Original author: Oliver Jaksch
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// Top
difference() {
    $fn=150;
    minkowski() {
        cube([28.17, 59.27, 21.0], true);
        cylinder(0.2, 1.5);
    }
    // Frame only
    translate ([0, 0, 1.35]) cube([27.37, 58.47, 24], true);
    // Frame and closing lid
    //translate ([0, 0, -3.35]) cube([27.37, 58.47, 24], true);

    // Cutout Tang Nano 20k HDMI
    translate ([0, 30, 7]) cube([16, 3, 8], true);
    // Cutout Tang Nano 20k USB-C
    translate ([0, -30, 2.5]) cube([15, 3, 10], true);

    // Cutout for USB-C/RPi
    translate ([0, 30.1, -7.6]) cube([15, 3, 6], true);
    // Cutout for USB-A/RPi
    ////translate ([0, -29.4, -0.1]) cube([14.5, 0.5, 21], true);
    translate ([0, -30, -6.5]) cube([15, 3, 8.1], true);

    // Cutout Tang Nano 20k Display
    // 6mm from the top edge, width 24mm, height 2mm
    // NOT TESTED
    //translate ([14.5, 8, 3.7]) cube([2.5, 24, 2], true);
}
