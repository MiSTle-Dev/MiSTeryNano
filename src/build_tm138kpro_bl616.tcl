set_device GW5AST-LV138FPG676AES -name GW5AST-138B

add_file atarist/acia.v
add_file atarist/acsi.v
add_file atarist/atarist.v
add_file atarist/cubase2_dongle.v
add_file atarist/cubase3_dongle.v
add_file atarist/dma.v
add_file atarist/io_fifo.v
add_file atarist/mfp.v
add_file atarist/mfp_hbit16.v
add_file atarist/mfp_srff16.v
add_file atarist/mfp_timer.v
add_file atarist/stBlitter.sv
add_file atarist/ste_joypad.v
add_file fdc1772/fdc1772.v
add_file fdc1772/floppy.v
add_file fx68k/fx68k.sv
add_file fx68k/fx68kAlu.sv
add_file fx68k/uaddrPla.sv
add_file gstmcu/hdl/clockgen.v
add_file gstmcu/hdl/gstmcu.v
add_file gstmcu/hdl/gstshifter.v
add_file gstmcu/hdl/hdegen.v
add_file gstmcu/hdl/hsyncgen.v
add_file gstmcu/hdl/latch.v
add_file gstmcu/hdl/mcucontrol.v
add_file gstmcu/hdl/modules.v
add_file gstmcu/hdl/register.v
add_file gstmcu/hdl/shifter_video.v
add_file gstmcu/hdl/sndcnt.v
add_file gstmcu/hdl/vdegen.v
add_file gstmcu/hdl/vidcnt.v
add_file gstmcu/hdl/vsyncgen.v
add_file hdmi/audio_clock_regeneration_packet.sv
add_file hdmi/audio_info_frame.sv
add_file hdmi/audio_sample_packet.sv
add_file hdmi/auxiliary_video_information_info_frame.sv
add_file hdmi/hdmi.sv
add_file hdmi/packet_assembler.sv
add_file hdmi/packet_picker.sv
add_file hdmi/serializer.sv
add_file hdmi/source_product_description_info_frame.sv
add_file hdmi/tmds_channel.sv
add_file ikbd/hd63701/HD63701.v
add_file ikbd/hd63701/HD63701_ALU.v
add_file ikbd/hd63701/HD63701_CORE.v
add_file ikbd/hd63701/HD63701_EXEC.v
add_file ikbd/hd63701/HD63701_MCODE.i
add_file ikbd/hd63701/HD63701_MCROM.v
add_file ikbd/hd63701/HD63701_SEQ.v
add_file ikbd/hd63701/HD63701_defs.i
add_file ikbd/ikbd.sv
add_file ikbd/rom/MCU_BIROM.v
add_file jt49/filter/jt49_dcrm.v
add_file jt49/filter/jt49_dcrm2.v
add_file jt49/filter/jt49_dly.v
add_file jt49/filter/jt49_mave.v
add_file jt49/jt49.v
add_file jt49/jt49_bus.v
add_file jt49/jt49_cen.v
add_file jt49/jt49_div.v
add_file jt49/jt49_eg.v
add_file jt49/jt49_exp.v
add_file jt49/jt49_noise.v
add_file misc/hid.v
add_file misc/mcu_spi.v
add_file misc/osd_u8g2.v
add_file misc/scandoubler.v
add_file misc/sd_card.v
add_file misc/sd_rw.v
add_file misc/sdcmd_ctrl.v
add_file misc/sysctrl.v
add_file misc/video_analyzer.v
add_file misc/dualshock2.v
add_file misc/atarist_keymap.v
add_file misterynano.sv
add_file tang/mega138k/flash_dspi.v
add_file tang/mega138k/sdram.v
add_file tang/mega138kpro_bl616/top.sv
add_file tang/nano20k/video.v
add_file tang/nano20k/video2hdmi.v
add_file tang/nano20k/ws2812.v
add_file tang/mega138k/gowin_clkdiv/gowin_clkdiv.v
add_file tang/mega138k/gowin_dpb/fdc_dpram.v
add_file tang/mega138k/gowin_dpb/sector_dpram.v
add_file tang/mega138k/gowin_pll/flash_pll.v
add_file tang/mega138k/gowin_pll/pll_160m.v
add_file tang/mega138kpro_bl616/atarist.cst
add_file tang/mega138kpro_bl616/atarist.sdc
add_file fx68k/microrom.mem
add_file fx68k/nanorom.mem
add_file ikbd/rom/ikbd.hex
add_file misc/atarist_xml.hex

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name atarist_tm138kpro_bl616
set_option -verilog_std sysv2017
set_option -top_module top
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_jtag_as_gpio 1
set_option -bit_compress 1
set_option -multi_boot 0
set_option -mspi_jump 0
set_option -cst_warn_to_error 1
set_option -loading_rate 70.000

run all
