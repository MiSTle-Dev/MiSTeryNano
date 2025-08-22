// A simple case for the MiSTeryNano Lite  (https://github.com/harbaum/MiSTeryNano)

// Original author: Oliver Jaksch
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// The used "Commodore-Font" is copyrighted but "Free for Personal Use"
// https://befonts.com/gyrotrope-font-family.html

// The C64 logo is borrowed from user "syntonia" (https://www.thingiverse.com/thing:2396696)
// CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)

// The Badge

font = "Gyrotrope:style=Bold"; // Must be installed in your system and named correctly!
letter_size = 7;
letter_height = 0.5;
holediameter = 8;

module letter(l) {
    // Use linear_extrude() to make the letters 3D objects as they
    // are only 2D shapes when only using text()
    linear_extrude(height = letter_height) {
        text(l, size = letter_size, font = font, halign = "center", valign = "center", $fn = 60);
    }
}

// Base Plate
color("PaleGreen") cube([62, 10, 0.5], true);

// C64 Logo
translate([-20, -20.9, 0.25]) scale([0.07, 0.07, 0.03])import("logos/commodore1.stl", center = true);

// Stripes
for (step =[-3:1.6:4]) translate ([-10, step, 0.5]) cube([12, 1, 0.5], true);

// Text
translate([13, 0, 0.25]) letter("C64");
