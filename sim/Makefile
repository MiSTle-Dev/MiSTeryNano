#
# Makefile
#

PRJ=atarist

OBJ_DIR=obj_dir

# the original fx68k won't simulate. Thus we use this special version for simulation
FX68K_DIR=./fx68x_verilator
FX68K_FILES= fx68k.sv fx68kAlu.sv uaddrPla.sv fx68k_MicroRom.v fx68k_NanoRom.v

# 
TB=atarist_tb

GSTMCU_DIR=../src/gstmcu/hdl
GSTMCU_FILES=gstmcu.v clockgen.v mcucontrol.v hsyncgen.v hdegen.v vsyncgen.v vdegen.v vidcnt.v sndcnt.v latch.v register.v modules.v gstshifter.v shifter_video.v shifter_video_async.v

ATARIST_DIR=../src/atarist
ATARIST_FILES= mfp.v mfp_hbit16.v  mfp_srff16.v mfp_timer.v io_fifo.v acia.v stBlitter.sv ste_joypad.v dma.v acsi.v atarist.v cubase2_dongle.v cubase3_dongle.v

FDC_DIR=../src/fdc1772
FDC_FILES= fdc1772.v floppy.v

JT49_DIR=../src/jt49
JT49_FILES= jt49_bus.v  jt49_cen.v  jt49_div.v  jt49_eg.v  jt49_exp.v  jt49_noise.v  jt49.v filter/jt49_dcrm2.v  filter/jt49_dcrm.v  filter/jt49_dly.v  filter/jt49_mave.v

IKBD_DIR=../src/ikbd
IKBD_FILES= ikbd.sv hd63701/HD63701_ALU.v hd63701/HD63701_CORE.v hd63701/HD63701_EXEC.v hd63701/HD63701_MCROM.v hd63701/HD63701_SEQ.v hd63701/HD63701.v rom/MCU_BIROM.v

MISC_DIR=../src/misc
MISC_FILES=video_analyzer.v scandoubler.v

MISC_FILES+=sd_card.v sd_rw.v sdcmd_ctrl.v

VERILATOR_DIR=/usr/local/share/verilator/include
VERILATOR_FILES=verilated.cpp verilated_vcd_c.cpp verilated_threads.cpp

HDL_FILES=$(TB).v $(GSTMCU_FILES:%=$(GSTMCU_DIR)/%) $(FX68K_FILES:%=$(FX68K_DIR)/%) $(ATARIST_FILES:%=$(ATARIST_DIR)/%) $(FDC_FILES:%=$(FDC_DIR)/%) $(IKBD_FILES:%=$(IKBD_DIR)/%) $(JT49_FILES:%=$(JT49_DIR)/%) $(MISC_FILES:%=$(MISC_DIR)/%)

EXTRA_CFLAGS = `sdl2-config --cflags`
EXTRA_LDFLAGS = `sdl2-config --libs` -lSDL2_image

all: $(PRJ)

$(PRJ): $(TB).cpp sd_card.cpp sd_card_config.h ${HDL_FILES} Makefile
	verilator -O3 -Wno-fatal --no-timing --trace-fst --threads 1 --trace-underscore -I$(IKBD_DIR)/hd63701 -top-module $(PRJ)_tb $(VERILATOR_FLAGS) -cc ${HDL_FILES} --exe $(TB).cpp sd_card.cpp -o ../$(PRJ) -CFLAGS "${EXTRA_CFLAGS}" -LDFLAGS "${EXTRA_LDFLAGS}"
	make -j -C ${OBJ_DIR} -f V$(PRJ)_tb.mk

$(PRJ)_tb.fst: $(PRJ)
	./$(PRJ)

run: $(PRJ)
	./$(PRJ)

wave: $(PRJ)_tb.fst
	gtkwave $(PRJ)_tb.gtkw

clean:
	rm -rf obj_dir $(PRJ)
