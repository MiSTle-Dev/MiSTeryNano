# mkhdmenu.py

This is a small python script to build a bootable games harddisk image
for the Atari ST. It can build the image from scratch using preset directory
structures, files and ZIP files. This script is meant to be used with
```HDMENU``` and creates a matching CSV file for all games found.

The script will auto detect the AHDI and ICD harddisk drivers and will
install the matching bootloader. The AHDI bootloader will also work
with ```HDDriver``` and ```CBHD``` if their driver files are renamed
to ```SHDRIVER.SYS``` and being placed in the root of C:\.

## Automated usage

The ```mkhdmenu``` script can be run from a config file allowing it
to assemble complex hd images within a few seconds. Two examples
are included:

  - [```klapauzius.cfg```](klapauzius.cfg) creates a HDD image
    containing all the [Klapauzius patched games](http://www.klapauzius.net/Old_Games.html)
    with a nice menu. Some games unfortunately don't work with the menu.
  - [```thejoyofsticks_top50.cfg```](thejoyofsticks_top50.cfg) creates a HDD
  containing the [Joy of Sticks Top50 games](https://thejoyofsticks.co.uk/the-top-50-atari-st-games)

Besides the script itself the following files are needed:

  - ```SHDRIVER.SYS``` - The AHDI harddisk driver, Version 6.061, file size 13177  bytes
  - ```HDMENU.PRG``` e.g. from the [discussion on Atari Forum](https://www.atari-forum.com/viewtopic.php?t=43304)
  - ```NEOPICS.zip```, optional for screenshots, also from the [discussion on Atari Forum](https://www.atari-forum.com/viewtopic.php?t=43304)

These three files need to be places in the same directory as the python
script. This can then be invoked like:

```
$ ./mkhdmenu.py thejoyofsticks_top50.cfg 
```

The script will then download the games all by itself.

If everything goes to plan, then a file ```thejoyofsticks_top50.hd``` is generated.
This can be used as an ACSI HDD image and will then launch directly into
HDMenu allowing to select games.

![Screenshot](jos_top50_hdmenu.png)

## Manual usage

```
Usage mkhdmenu.py [options] <imagename|size|cfgfile> [commands...] [outname]
Options:
  -export-bootloader=<name>   if present export bootloaders from MBR and
                              bootsectors to <name>_mbr.bin and <name>_bootsector.bin
  -quiet                      print less output
<imagename|size>              name of existing hdd image to start with or size description
                              of the individual partitions like e.g. 16M+16384K for two
                              partitions of 16 megabytes each
Commands:
  dest=src                    copy src into the dest path in the image.
                              Src can be a zip file, a single regular file or
                              a entire directory like e.g.
                              C:\GAMES\BUBLGOST=zips/Bubble_Ghost.zip

Bootloaders for AHDI and ICD will be installed in the MBR and the bootsector of
partition C if a file named SHDRIVER.SYS (AHDI) or ICDBOOT.SYS (ICD) is being
included in partition C. This also works with hddriver and CBHD if they are being
(re-)named SHDRIVER.SYS
```


## Example

A single 16MB harddisk image using ```SHDRIVER.SYS``` (from AHDI) as a
bootloader, the Bubbleghost game from a ZIP file and three more games
from a local directory works like so:

```
./mkhdmenu.py 16M "C:\=./ICDBOOT.SYS" "C:\GAMES\BUBLGOST=game_zips/Bubble_Ghost_(Klapauzius).zip" "C:\=./disk" hdd16m.img
== mkhdmenu.py ==
Import ./ICDBOOT.SYS to C:\
Creating C:\ICDBOOT.SYS
Import game_zips/Bubble_Ghost_(Klapauzius).zip to C:\GAMES\BUBLGOST
Creating C:\GAMES\BUBLGOST\README.TXT
Creating C:\GAMES\BUBLGOST\BUBLGOST.KLP
Creating C:\GAMES\BUBLGOST\BUBLGOST.PRG
Import ./disk to C:\
Creating C:\GAMES\ARKANOI2\README.TXT
Creating C:\GAMES\ARKANOI2\ARKANOI2.PRG
Creating C:\GAMES\OIDS\OIDS.KLP
Creating C:\GAMES\OIDS\GRAVDROM.OID
Creating C:\GAMES\OIDS\INTERMED.OID
Creating C:\GAMES\OIDS\COSMOIDS.OID
Creating C:\GAMES\OIDS\README.TXT
Creating C:\GAMES\OIDS\NEWBEKUL.OID
Creating C:\GAMES\OIDS\TRIANGUL.OID
Creating C:\GAMES\OIDS\NOVOIDS.OID
Creating C:\GAMES\OIDS\OIDS.PRG
Creating C:\GAMES\DEFCROWN\README.TXT
Creating C:\GAMES\DEFCROWN\DEFCROWN.KLP
Creating C:\GAMES\DEFCROWN\DEFCROWN.PRG
Creating C:\AUTO\HDMENU.PRG
Creating C:\README.MD
Creating game list in C:\HDMENU.CSV...
Found game C:\GAMES\BUBLGOST\BUBLGOST.PRG
Found game C:\GAMES\ARKANOI2\ARKANOI2.PRG
Found game C:\GAMES\OIDS\OIDS.PRG
Found game C:\GAMES\DEFCROWN\DEFCROWN.PRG
== Files on partition C:\ ==
ICDBOOT.SYS          48502   19:43:54   30.10.2024
GAMES\
  BUBLGOST\
    README.TXT        5719   18:26:28   21.04.2012
    BUBLGOST.KLP     66784   18:45:36   21.04.2012
    BUBLGOST.PRG     25032   14:43:32   21.04.2012
  ARKANOI2\
    README.TXT        5646   12:42:44   14.04.2012
    ARKANOI2.PRG     81486   06:35:20   14.04.2012
  OIDS\
    OIDS.KLP         96288   23:43:24   30.12.2011
    GRAVDROM.OID     12134   04:57:24   27.12.2011
    INTERMED.OID      7082   11:50:04   07.01.2012
    COSMOIDS.OID      5398   11:50:02   07.01.2012
    README.TXT       21309   13:43:26   11.06.2012
    NEWBEKUL.OID     10450   04:57:24   27.12.2011
    TRIANGUL.OID     13818   04:57:24   27.12.2011
    NOVOIDS.OID       7082   11:50:06   07.01.2012
    OIDS.PRG         20692   13:40:48   11.06.2012
  DEFCROWN\
    README.TXT       38025   16:44:18   13.03.2012
    DEFCROWN.KLP    379778   16:33:14   18.12.2009
    DEFCROWN.PRG     54580   15:52:48   13.03.2012
HDMENU.CFG             168   20:15:56   30.10.2024
AUTO\
  HDMENU.PRG        182002   18:09:12   21.10.2024
README.MD            30157   18:09:12   21.10.2024
HDMENU.CSV             152   21:16:16   30.10.2024
== Statistics ==
Total number of directories:      7
Total number of files:            22
Total data bytes:                 1112284
== writing 'hdd16m.img' ==
Partition C: contains ICD ICDBOOT.SYS
Writing MBR
Including ICD MBR bootloader
Creating Partition C:
Including ICD bootsector
Writing FATs ...
Writing root directory ...
Writing data ...
```
