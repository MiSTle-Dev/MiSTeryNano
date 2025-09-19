// A simple case for the MiSTeryNano Lite  (https://github.com/harbaum/MiSTeryNano)

// Original author: Oliver Jaksch
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// The Apple IIe badge is borrowed from user "option8" (https://www.thingiverse.com/thing:2630934)
// CC BY-SA (https://creativecommons.org/licenses/by-sa/3.0/)

// The Badge

// Base Plate
color("PaleGreen") cube([62, 10, 0.5], true);
translate([-312.8, -101.95, -0.58]) scale([1, 0.85, 1]) import("logos/Apple_IIe_Badge_pin.stl");
