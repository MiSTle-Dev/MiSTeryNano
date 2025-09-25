/*
    top.sv - atarist on tang mega 138k toplevel

    This top level implements the default variant for 138k
*/ 

module top(
  input 		clk, // 50 MHz in

  input 		reset_n, // S2
  input 		user_n, // S1

  output [5:0] 	leds_n,
  output 		ws2812,

  // spi flash interface
  output 		mspi_cs,
  output 		mspi_clk,
  inout 		mspi_di,
  inout 		mspi_hold,
  inout 		mspi_wp,
  inout 		mspi_do,

  // MiSTer SDRAM module
  output 		O_sdram_clk,
  output 		O_sdram_cs_n, // chip select
  output 		O_sdram_cas_n, // columns address select
  output 		O_sdram_ras_n, // row address select
  output 		O_sdram_wen_n, // write enable
  inout [15:0] 	IO_sdram_dq, // 16 bit bidirectional data bus
  output [12:0] O_sdram_addr, // 13 bit multiplexed address bus
  output [1:0] 	O_sdram_ba, // two banks
  output [1:0] 	O_sdram_dqm, // 16/2

  // interface to external BL616/M0S on middle PMOD
  inout [7:0] 	m0s,

  // two dual shock controllers on left PMOD, only P1 is used
  // by MiSTeryNano for joystick
  output 		ds1_csn,
  output 		ds1_sclk,
  output 		ds1_mosi,
  input 		ds1_miso,
  output 		ds2_csn,
  output 		ds2_sclk,
  output 		ds2_mosi,
  input 		ds2_miso,		   

  // SD card slot
  output 		sd_clk,
  inout 		sd_cmd, // MOSI
  inout [3:0] 	sd_dat, // 0: MISO

  output 		lcd_clk,
  output 		lcd_en, //lcd data enable     
  output [5:0] 	lcd_r, //lcd red
  output [5:0] 	lcd_g, //lcd green
  output [5:0] 	lcd_b, //lcd blue
  output 		lcd_bl, //drive low to turn bl off

  // I2S DAC
  output 		i2s_bclk,
  output 		i2s_lrck,
  output 		i2s_din,
  output 		pa_en,
	   
  // hdmi/tdms
  output 		tmds_clk_n,
  output 		tmds_clk_p,
  output [2:0] 	tmds_d_n,
  output [2:0] 	tmds_d_p
);

wire clk32;
wire pll_lock_hdmi;
wire por; 

// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
assign m0s[7:0] = { 3'bzzz, spi_intn, 3'bzzz, spi_io_dout };

// switch between internal SPI connected to the on-board bl616
// or to the external one possibly connected to a M0S Dock
wire spi_io_din = m0s[1];
wire spi_io_ss = m0s[2];
wire spi_io_clk = m0s[3];

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire        vwide;

assign lcd_bl = 1'bz;
   
// MiSTer SDRAM is only 16 bits wide
wire [31:0] sdram_dq;  
assign IO_sdram_dq = sdram_dq[15:0];
   
wire [3:0] sdram_dqm;  
assign O_sdram_dqm = sdram_dqm[1:0];

// ------ dual shock interface ------------

wire    lcd_vs_n;   
assign ds2_csn = 1'b1;   

// signals coming from dualshock2 p1
wire [4:0] ds1_p1;   

assign ds1_p1[0] = |ds1_buttons;
wire [3:0] ds1_buttons;   
   
dualshock2 ds2_p1 (
  .clk          ( clk32     ), // ds2 module actually expects 31.5 Mhz
  .rst          ( por       ),			   
  .vsync        ( !lcd_vs_n ), // refresh once a screen
				   
  .ds2_dat      ( ds1_miso  ), // connections to dualshock p1 port
  .ds2_cmd      ( ds1_mosi  ),
  .ds2_att      ( ds1_csn   ),
  .ds2_clk      ( ds1_sclk  ),
  .ds2_ack      (           ),

  .key_down     ( ds1_p1[1] ),
  .key_up       ( ds1_p1[2] ),
  .key_right    ( ds1_p1[3] ),
  .key_left     ( ds1_p1[4] ),

  .key_triangle ( ds1_buttons[0] ),
  .key_circle   ( ds1_buttons[1] ),
  .key_cross    ( ds1_buttons[2] ),
  .key_square   ( ds1_buttons[3] )
);  

// ------ feed audio into i2s dac ------------
assign pa_en = 1'b1;   // enable headphone amplifier

// generate 48k * 32 = 1536kHz audio clock. TODO: this is too
// imprecise
reg clk_audio;
reg [7:0] aclk_cnt;
always @(posedge clk32) begin
    if(aclk_cnt < 32000000 / 1536000 / 2 -1)
        aclk_cnt <= aclk_cnt + 8'd1;
    else begin
        aclk_cnt <= 8'd0;
        clk_audio <= ~clk_audio;
    end
end

// count 32 bits
reg [4:0] audio_bit_cnt;
always @(posedge clk_audio) begin
    if(por)
        audio_bit_cnt <= 5'd0;
    else 
        audio_bit_cnt <= audio_bit_cnt + 5'd1;
end

// generate i2s signals
assign i2s_bclk = clk_audio;
assign i2s_lrck = por?1'b0:audio_bit_cnt[4];
assign i2s_din = por?1'b0:audio[i2s_lrck][15-audio_bit_cnt[3:0]];
   
misterynano misterynano (
  .clk   ( clk ),           // 50MHz clock uses e.g. for the flash pll

  .reset ( !reset_n ),
  .user  ( !user_n ),

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
  .sdram_cke   ( ),
  .sdram_cs_n  ( O_sdram_cs_n   ), // chip select
  .sdram_cas_n ( O_sdram_cas_n  ), // columns address select
  .sdram_ras_n ( O_sdram_ras_n  ), // row address select
  .sdram_wen_n ( O_sdram_wen_n  ), // write enable
  .sdram_dq    ( sdram_dq       ), // 16 bit bidirectional data bus
  .sdram_addr  ( O_sdram_addr   ), // 13 bit multiplexed address bus
  .sdram_ba    ( O_sdram_ba     ), // two banks
  .sdram_dqm   ( sdram_dqm      ), // 16/4

  // generic IO, used for mouse/joystick/...
  .io          ( { 3'b111, ~ds1_p1 } ),

  // mcu interface
  .mcu_sclk ( spi_io_clk  ),
  .mcu_csn  ( spi_io_ss   ),
  .mcu_miso ( spi_io_dout ), // from FPGA to MCU
  .mcu_mosi ( spi_io_din  ), // from MCU to FPGA
  .mcu_intn ( spi_intn    ),

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
  .lcd_clk  ( lcd_clk  ),
  .lcd_hs_n (          ),
  .lcd_vs_n ( lcd_vs_n ),
  .lcd_de   ( lcd_en   ),
  .lcd_r    ( lcd_r    ),
  .lcd_g    ( lcd_g    ),
  .lcd_b    ( lcd_b    ),

  // digital 16 bit audio output
  .audio ( audio )
);


video2hdmi video2hdmi (
    .clk      ( clk      ),       // clock in
    .clk_32   ( clk32    ),       // 32 Mhz clock out
    .pll_lock ( pll_lock_hdmi ),  // output clock is stable

    .vreset ( vreset ),
    .vmode ( vmode ),
    .vwide ( vwide ),

    .r( lcd_r ),
    .g( lcd_g ),
    .b( lcd_b ),
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

