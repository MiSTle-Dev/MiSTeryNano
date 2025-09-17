# MiSTeryNano on Tang Primer 25K

MiSTeryNano can be used in the [Tang Primer 25K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html). This offers a 10%
bigger FPGA than the [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
the MiSTeryNano was initially developed for. Unlike the TN20K, the
TP25k's FPGA does not come with an internal SDRAM. Nor does the board
come with HDMI or an SD card slot.

Some SDRAM can be added in the form of the [Tang SDRAM](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#TANG_SDRAM), HDMI can be added via the [PMOD DVI](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DVI) and the SD card is installed using the [PMOD TF-CARD](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_TF-CARD). All three add-ons need to carefully be mounted with the SDRAM's "THIS SIDE FACES OUTWARD" pointing to the boards edge. The HDMI needs to be mounted to the leftmost PMOD slot andf the SD card to the rightmost.

The M0S required to control the MiSTeryNano is to be mounted in the middle PMOD with the help of the [M0S PMOD adapter](board/m0s_pmod).

The whole setup will look like this:
![MiSTeryNano on TP25K](https://github.com/MiSTle-Dev/Boards/blob/main/m0s_pmod/m0s_pmod_tp25k.jpg)

On the software side the setup is very simuilar to the original Tang Nano 20K based solution. The core needs to be built specifically
for the different FPGA of the Tang Primer using either the [TCL script with the GoWin command line interface](src/build_tp25k.tcl) or the
[project file for the graphical GoWin IDE](src/atarist_tp25k.gprj). The resulting bitstream is flashed to the TP25K as usual. So are the TOS ROMs which are flashed exactly like they are on the Tang Nano 20K. And also the firmware for the M0S Dock is the [same version as for
the Tang Nano 20K](firmware/misterynano_fw/).

The resulting setup has no spare connectors and thus no MIDI or DB9 retro joystick port is available.
