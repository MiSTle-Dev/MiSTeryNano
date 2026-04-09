create_clock -name clk_hdmi -period 6.25 -waveform {0 3.125} [get_ports {clk_pixel_x5}] -add
create_clock -name clk_spi -period 10 -waveform {0 5} [get_ports {mspi_clk}] -add
create_clock -name clk_32 -period 31 -waveform {0 15} [get_ports {clk_pixel}] -add
create_clock -name clk_sdram -period 31 -waveform {0 15} [get_ports {SDRAM_CLK}] -add
create_clock -name clk_sd -period 125 -waveform {0 62} [get_ports {sd_clk}] -add
