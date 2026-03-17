# MiSTeryNano Simulation

When used under Linux the ```Gowin Analyzer Oscilloscope (GAO)``` cannot
be used due to incompatibilities between the GoWin Programmer software and
the programmer hardware of the Tang Nano 20k.

To cope with this, most development of the MiSTeryNano was done using
a [Verilator](https://www.veripool.org/verilator/) simulation. At least
version 5.015 is needed for these simulations.

A ```make wave``` will compile and run the simulation and will show
the resulting waveforms in gtkview.

This testbench simulates the complete Atari ST incl. video, floppy and
ACSI harddisk. The simulated Atari runs at less than 1% real speed
depending on the speed of your PC. This allows for extensive debugging
of the Atari ST core and can even be used to boot games and demos.
