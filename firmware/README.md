# Old firmware

This directory contains an old version of the firmware. The firmware is now developed as a seperate project in the
[FPGA Companion repository](https://github.com/harbaum/FPGA-Companion).

## USB HID

The [usb_hid](usb_hid) has been used up to version 1.1.0 of MiSTeryNano. It provided
PS2 like interfaces for keyboard and mouse. Later version switch to a SPI interface
for keyboard and mouse and also include more functionality including OSD control.
The [usb_hid](usb_hid) is here for reference and since other projects may have a use
for a simple and cheap USB/PS2 conversion.

### USB HID on M0S Dock

The [usb_hid](usb_hid) code lets the
[M0S Dock](https://wiki.sipeed.com/hardware/en/maixzero/m0s/m0s.html)
act as a USB host accepting USB keyboards and mice and converting their
signals into [PS/2](https://en.wikipedia.org/wiki/PS/2_port)
compatible signals as used by many retro computing FPGA cores to
interface to keyboards and mice.

A LED on the M0S Dock will light up, when a HID device is detected (e.g. a keyboard,
mouse or joystick). Keyboard signals will be sent via IO10 (CLK) and IO11 (DATA) and
mouse signals will be sent via IO12 (CLK) and IO13 (DATA). Furthermore GND and +5V have to
be connected to the Tang Nano 20k to power the M0S Dock and its attached USB devices.

See a demo video [here](https://youtube.com/shorts/jjps1x1NjhE?si=LUqlXd3iTG0hus1-).

This has been tested with several wireless keyboard/touchpad combo devices incl.
the Rii X1 and the Rapoo E2710.

### USB HID with the internal BL616 MCU of the Tang Nano 20k

While it's recommanded to use an external M0S Dock it's also possible to repurpose
the internal BL616 MCU to handle mouse and keyboard. This possibility is a work in progress and not every release of the firmware may be ready to be used on the internal BL616 MCU. 

Before compiling the new firmware as described above, the
```M0S_DOCK``` define has to be commented in
[usb_config.h](https://github.com/harbaum/MiSTeryNano/blob/ffd647f3c8f8406800e98a099cbf70ec7bcb20e8/firmware/usb_hid/usb_config.h#L9)
to make sure that the generated code works for the internal BL616 MCU.

Finally the BL616 MCU is re-flashed with the USB HID firmware. This way you'll
loose the ability to flash the FPGA! Before being able to re-flash the FPGA
you need to re-install the original firmware. The original firmware is available [here](friend_20k).
