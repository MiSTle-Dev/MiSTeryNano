/*
    top.sv - atarist on mistle g25a dev25k toplevel

    This top level implements the default variant for 25k
*/ 

`define GOWIN

module top(
  input			clk, // 50 MHz in

  input			reset, // S2
  input			user_n, // S1

  output [5:0]	leds_n,

  // spi flash interface
  output		mspi_cs,
  output		mspi_clk,
  inout			mspi_di,
  inout			mspi_hold,
  inout			mspi_wp,
  inout			mspi_do,

  // MiSTer SDRAM module
  output		O_sdram_clk,
  output		O_sdram_cs_n, // chip select
  output		O_sdram_cas_n, // column address select
  output		O_sdram_ras_n, // row address select
  output		O_sdram_wen_n, // write enable
  inout [15:0]	IO_sdram_dq, // 16 bit bidirectional data bus
  output [12:0]	O_sdram_addr, // 13 bit multiplexed address bus
  output [1:0]	O_sdram_ba, // two banks
  output [1:0]	O_sdram_dqm, // 16/2

  // give explicit directions for pmod1 as it's being used for the
  // FPGA Companion and this allows for clock buffering. Clock glitches
  // were observed when using inouts for the companion
  input			pmod_companion_din,
  output		pmod_companion_dout,
  input			pmod_companion_clk,
  input			pmod_companion_ss,
  output		pmod_companion_intn,
  input			pmod_companion_spare,

  // generic IO, used for mouse/joystick/...
  input [5:0]	joya,
  input [5:0]	joyb,

  // generaic extension
  inout [5:0]	ext,

  // MIDI
  input			midi_in,
  output		midi_out,
		   
  // SD card slot
  output		sd_clk,
  inout			sd_cmd, // MOSI
  inout [3:0]	sd_dat, // 0: MISO

  output		ws2812,
		   
  // hdmi/tdms
  output		tmds_clk_n,
  output		tmds_clk_p,
  output [2:0]	tmds_d_n,
  output [2:0]	tmds_d_p
);


wire clk32;
wire pll_lock;
wire flash_clk;
wire por = !pll_lock;

// -------------------------- FPGA Companion interface -----------------------

// map output data onto both spi outputs
wire spi_io_dout;
wire spi_intn;

// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
wire spi_io_dout;
wire spi_intn;
assign pmod_companion_dout = spi_io_dout;
assign pmod_companion_intn = spi_intn;

wire spi_io_din = pmod_companion_din;
wire spi_io_ss = pmod_companion_ss;
wire spi_io_clk = pmod_companion_clk;

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire [1:0]  screen;

wire [5:0]  r;
wire [5:0]  g;
wire [5:0]  b;

// MiSTer SDRAM is only 16 bits wide
wire [31:0] sdram_dq;  
assign IO_sdram_dq = sdram_dq[15:0];
   
wire [3:0] sdram_dqm;  
assign O_sdram_dqm = sdram_dqm[1:0];

misterynano misterynano (
  .reset ( reset ),
  .user  ( !user_n ),

  // clock and power on reset from system
  .clk32 ( clk32 ),         // 32 Mhz system clock input
  .flash_clk ( flash_clk ), 
  .por   ( por ),           // True while not all PLLs locked

  .leds_n ( leds_n ),
  .ws2812 ( ws2812 ),

  // spi flash interface
  .mspi_cs   ( mspi_cs   ),
  .mspi_di   ( mspi_di   ),
  .mspi_hold ( mspi_hold ),
  .mspi_wp   ( mspi_wp   ),
  .mspi_do   ( mspi_do   ),

  // SDRAM
  .sdram_clk   ( ),
  .sdram_cke   ( ),
  .sdram_cs_n  ( O_sdram_cs_n   ), // chip select
  .sdram_cas_n ( O_sdram_cas_n  ), // column address select
  .sdram_ras_n ( O_sdram_ras_n  ), // row address select
  .sdram_wen_n ( O_sdram_wen_n  ), // write enable
  .sdram_dq    ( sdram_dq       ), // 16 bit bidirectional data bus
  .sdram_addr  ( O_sdram_addr   ), // 13 bit multiplexed address bus
  .sdram_ba    ( O_sdram_ba     ), // two banks
  .sdram_dqm   ( sdram_dqm      ), // 16/4

  // generic IO, used for mouse/joystick/...
  .io    ( joya ),
  .spare ( joyb ),

  // mcu interface
  .mcu_sclk ( spi_io_clk  ),
  .mcu_csn  ( spi_io_ss   ),
  .mcu_miso ( spi_io_dout ), // from FPGA to MCU
  .mcu_mosi ( spi_io_din  ), // from MCU to FPGA
  .mcu_intn ( spi_intn    ),

   // parallel port is not implemented

   // midi
   .midi_in  ( midi_in  ),					 
   .midi_out ( midi_out ),					 
		   
  // SD card slot
  .sd_clk ( sd_clk ),
  .sd_cmd ( sd_cmd ), // MOSI
  .sd_dat ( sd_dat ), // 0: MISO

  .vreset ( vreset ),
  .vmode  ( vmode  ),
  .screen ( screen ),
	   
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

wire	   clk_pixel_x5;
wire	   clk_pixel;   
pll_160m pll_hdmi (
               .clkout0(clk_pixel_x5),       // 158.333 MHz
               .clkout1(clk_pixel),          // 31.66 MHz
               .clkout2(O_sdram_clk),        // 31.66 MHz, shifted by 337,5°
               .clkout3(flash_clk),          // 95 MHz
               .clkout4(mspi_clk),           // 95 MHz, shifted by 22,5°
               .lock(pll_lock),
               .clkin(clk),
               .reset(1'b0),
               .mdclk(clk) 
       );

assign clk32 = clk_pixel;   // the 32 Mhz system clock is the pixel clock

video2hdmi #(.PIXEL_CLOCK(31_666_666)) video2hdmi (
    .clk_pixel_x5 ( clk_pixel_x5  ),      // hdmi clock
    .clk_pixel    ( clk_pixel     ),      // pixel clock
  
    .vreset ( vreset ),
    .vmode ( vmode ),
    .screen ( screen ),

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

