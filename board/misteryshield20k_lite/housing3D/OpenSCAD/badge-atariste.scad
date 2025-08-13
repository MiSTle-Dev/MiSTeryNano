// A simple case for the MiSTeryNano Lite  (https://github.com/harbaum/MiSTeryNano)

// Original author: Oliver Jaksch
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// The used "Atari-Font" is copyrighted but "Free for Personal Use"
// https://befonts.com/rawles.charmap

// The Badge

font = "Rawles"; // Must be installed in your system and named correctly!
letter_size = 7;
letter_height = 0.5;
holediameter = 8;

module letter(l) {
    // Use linear_extrude() to make the letters 3D objects as they
    // are only 2D shapes when only using text()
    linear_extrude(height = letter_height) {
        text(l, size = letter_size, font = font, halign = "center", valign = "center", $fn = 25);
    }
}

// Base Plate
color("PaleGreen") cube([62, 10, 0.5], true);

// Atari Logo
translate([-26, -3.9, 0.25]) scale([0.026, 0.026, 1])
linear_extrude(height = 0.5)
import("logos/fuji2.dxf");

// Text
translate([6, 0, 0.25]) letter("ATARI ST/E");
