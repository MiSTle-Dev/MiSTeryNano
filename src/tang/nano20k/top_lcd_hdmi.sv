/*
    top_lcd_hdmi.sv - atarist on tang nano 20k toplevel

    This top level implements the default variant for 20k with FPGA Companion
    connected on the same pins as LCD version.
*/ 

module top(
  input			clk,

  input			reset, // S2
  input			user, // S1

  output [5:0]	leds_n,
  output		ws2812,

  // spi flash interface
  output		mspi_cs,
  output		mspi_clk,
  inout			mspi_di,
  inout			mspi_hold,
  inout			mspi_wp,
  inout			mspi_do,

  // "Magic" port names that the gowin compiler connects to the on-chip SDRAM
  output		O_sdram_clk,
  output		O_sdram_cke,
  output		O_sdram_cs_n, // chip select
  output		O_sdram_cas_n,
    
 // columns address select
  output		O_sdram_ras_n, // row address select
  output		O_sdram_wen_n, // write enable
  inout [31:0]	IO_sdram_dq, // 32 bit bidirectional data bus
  output [10:0]	O_sdram_addr, // 11 bit multiplexed address bus
  output [1:0]	O_sdram_ba, // two banks
  output [3:0]	O_sdram_dqm, // 32/4


  // interface to RP2040
  inout [4:0]	fpga_companion,

  // SD card slot
  output		sd_clk,
  inout			sd_cmd, // MOSI
  inout [3:0]	sd_dat, // 0: MISO
	   

  // hdmi/tdms
  output		tmds_clk_n,
  output		tmds_clk_p,
  output [2:0]	tmds_d_n,
  output [2:0]	tmds_d_p
);

wire clk32;
wire pll_lock_hdmi;

wire        por;

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire        vwide;

wire [5:0]  r;
wire [5:0]  g;
wire [5:0]  b;

// sdram address can be up to 13 bits wide. tang nano 20k uses only 11
wire [13:0] sdram_addr;
assign O_sdram_addr = sdram_addr[10:0];

misterynano misterynano (
  .clk   ( clk ),           // 27MHz clock uses e.g. for the flash pll

  .reset ( reset ),
  .user  ( user ),

  // clock and power on reset from system
  .clk32 ( clk32 ),         // 32 Mhz system clock input
  .pll_lock_main( pll_lock_hdmi),
  .por   ( por ),           // output. True while not all PLLs locked

  .leds_n ( leds_n ),
  .ws2812 ( ws2812 ),

  // spi flash interface
  .mspi_cs   ( mspi_cs   ),
  .mspi_clk  ( mspi_clk  ),
  .mspi_di   ( mspi_di   ),
  .mspi_hold ( mspi_hold ),
  .mspi_wp   ( mspi_wp   ),
  .mspi_do   ( mspi_do   ),

  // SDRAM
  .sdram_clk   ( O_sdram_clk    ),
  .sdram_cke   ( O_sdram_cke    ),
  .sdram_cs_n  ( O_sdram_cs_n   ), // chip select
  .sdram_cas_n ( O_sdram_cas_n  ), // columns address select
  .sdram_ras_n ( O_sdram_ras_n  ), // row address select
  .sdram_wen_n ( O_sdram_wen_n  ), // write enable
  .sdram_dq    ( IO_sdram_dq    ), // 32 bit bidirectional data bus
  .sdram_addr  ( sdram_addr     ), // 11 bit multiplexed address bus
  .sdram_ba    ( O_sdram_ba     ), // two banks
  .sdram_dqm   ( O_sdram_dqm    ), // 32/4

  // generic IO, used for mouse/joystick/...
  .io ( 8'b11111111 ),

  // mcu interface
  .mcu_sclk ( fpga_companion[3]      ),
  .mcu_csn  ( fpga_companion[2]      ),
  .mcu_miso ( fpga_companion[0]      ), // from FPGA to MCU
  .mcu_mosi ( fpga_companion[1]      ), // from MCU to FPGA
  .mcu_intn ( fpga_companion[4]      ),
 
  // parallel port and MIDI are not implemented
		   
  // SD card slot
  .sd_clk ( sd_clk ),
  .sd_cmd ( sd_cmd ), // MOSI
  .sd_dat ( sd_dat ), // 0: MISO

  .vreset ( vreset ),
  .vmode  ( vmode  ),
  .vwide  ( vwide  ),
	   
  // scandoubled digital video to be
  // used with lcds
  .lcd_clk  ( ),
  .lcd_hs_n ( ),
  .lcd_vs_n ( ),
  .lcd_de   ( ),
  .lcd_r    ( r ),
  .lcd_g    ( g ),
  .lcd_b    ( b ),

  // digital 16 bit audio output
  .audio ( audio )
);

video2hdmi video2hdmi (
    .clk      ( clk      ),       // 27 Mhz clock in
    .clk_32   ( clk32    ),       // 32 Mhz clock out
    .pll_lock ( pll_lock_hdmi ),  // output clock is stable

    .vreset ( vreset ),
    .vmode ( vmode ),
    .vwide ( vwide ),

    .r( r ),
    .g( g ),
    .b( b ),
    .audio ( audio ),
    
    // tdms to be used with hdmi or dvi
    .tmds_clk_n ( tmds_clk_n ),
    .tmds_clk_p ( tmds_clk_p ),
    .tmds_d_n   ( tmds_d_n   ),
    .tmds_d_p   ( tmds_d_p   )
);

endmodule

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:

