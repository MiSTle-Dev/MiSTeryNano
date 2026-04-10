#!/bin/bash
cd efinix/t20_bga256

# if nothing else specified, then do a build first and then
# an sram upload
if [ $# -eq 0 ]; then
    set -- build load
fi

if [ "$EFINITY_HOME" == "" ]; then
    echo "Please set EFINITY_HOME"
    exit -1
fi

# apply clear patch if needed
if [ "`grep SDRAM MiSTeryNano.peri.xml`" != "" ]; then
    echo "Clearing Design"
    patch -p0 < clear_design.patch
fi

for arg in "$@"; do
    if [ "$arg" == "build" ]; then
	EFINITY_USER_DIR_INI=~/.efinity EFXPT_HOME=$EFINITY_HOME/pt EFXPGM_HOME=$EFINITY_HOME/pgm $EFINITY_HOME/bin/efx_run --un_flow MiSTeryNano.xml -f compile
    elif [ "$arg" == "load" ]; then
	openFPGALoader -b trion_t20_bga256_jtag ./outflow/MiSTeryNano.bit
    elif [ "$arg" == "flash" ]; then
	openFPGALoader -b trion_t20_bga256 -f ./outflow/MiSTeryNano.hex
    elif [ "$arg" == "tos" ]; then
	openFPGALoader -b trion_t20_bga256 --external-flash -o 0x100000 ../../../tos104de.img
	openFPGALoader -b trion_t20_bga256 --external-flash -o 0x140000 ../../../tos162de.img
	openFPGALoader -b trion_t20_bga256 --external-flash -o 0x180000 ../../../tos206de.img
	openFPGALoader -b trion_t20_bga256 --external-flash -o 0x1c0000 ../../../tos206de.img
    else
	echo "Unknown command $arg"
	exit -1
    fi
done

echo "Done"
