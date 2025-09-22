/*
    top.sv - atarist on tang console 138k toplevel

    This top level implements the default variant for tc138k
*/ 

module top(
  input			clk, // 50 MHz in

  input			reset_n, // S2
  input			user_n, // S1

  output [1:0]	leds_n,

  // interface to Tang onboard BL616 UART
  input			uart_rx,
  output		uart_tx,
  // onboard Bl616 monitor console port interface
  output		bl616_mon_tx,
  input			bl616_mon_rx,

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
  output		O_sdram_cas_n, // columns address select
  output		O_sdram_ras_n, // row address select
  output		O_sdram_wen_n, // write enable
  inout [15:0]	IO_sdram_dq, // 16 bit bidirectional data bus
  output [12:0]	O_sdram_addr, // 13 bit multiplexed address bus
  output [1:0]	O_sdram_ba, // two banks
  output [1:0]	O_sdram_dqm, // 16/2

  // interface to external BL616/M0S on middle PMOD
  inout [4:0]	m0s,

  // interface to onboard BL616 µC
  input			spi_sclk, 
  input			spi_csn,
  output		spi_dir,
  input			spi_dat,
  output		spi_irqn,

  // two dual shock controllers on left PMOD, only P1 is used
  // by MiSTeryNano for joystick
  output		ds1_csn,
  output		ds1_sclk,
  output		ds1_mosi,
  input			ds1_miso,
  output		ds2_csn,
  output		ds2_sclk,
  output		ds2_mosi,
  input			ds2_miso, 

  // SD card slot
  output		sd_clk,
  inout			sd_cmd, // MOSI
  inout [3:0]	sd_dat, // 0: MISO

  output		lcd_clk,
  output		lcd_en, //lcd data enable     
  output		lcd_hs, //lcd data enable     
  output		lcd_vs, //lcd data enable     
  output [7:0]	lcd_r, //lcd red
  output [7:0]	lcd_g, //lcd green
  output [7:0]	lcd_b, //lcd blue
  output		lcd_bl, //drive low to turn bl off
		   
  // I2S DAC
  output		i2s_bclk,
  output		i2s_lrck,
  output		i2s_din,
  output		pa_en,
	   
  // hdmi/tdms
  output		tmds_clk_n,
  output		tmds_clk_p,
  output [2:0]	tmds_d_n,
  output [2:0]	tmds_d_p
);

// connect onboard BL616 console to hw pins for an USB-UART adapter
assign uart_tx = bl616_mon_rx;
assign bl616_mon_tx = uart_rx;

wire clk32;
wire pll_lock_hdmi;
wire por; 

// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
assign m0s[4:0] = { spi_intn, 3'bzzz, spi_io_dout };

// map output data onto both spi outputs
wire spi_io_dout;
wire spi_intn;

// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
assign spi_dir = spi_io_dout;
assign spi_irqn = spi_intn;

// by default the internal SPI is being used. Once there is
// a select from the external spi, then the connection is
// being switched
reg spi_ext;
always @(posedge clk32) begin
    if(por)
        spi_ext = 1'b0;
    else begin
        // spi_ext is activated once the m0s pins 2 (ss or csn) is
        // driven low by the m0s dock. This means that a m0s dock
        // is connected and the FPGA switches its inputs to the
        // m0s. Until then the inputs of the internal BL616 are
        // being used.
        if(m0s[2] == 1'b0)
//          spi_ext = 1'b1; // auto switchover disabled !!!
            spi_ext = 1'b0; // workaround for AST138K
    end
end

// switch between internal SPI connected to the on-board BL616 µC
// or to the external connected M0S Dock or PiPico
wire spi_io_din = spi_ext?m0s[1]:spi_dat;
wire spi_io_ss = spi_ext?m0s[2]:spi_csn;
wire spi_io_clk = spi_ext?m0s[3]:spi_sclk;

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire        vwide;

wire [5:0] leds_int_n;
assign leds_n = ~leds_int_n[1:0];

assign lcd_bl = 1'bz;
   
// MiSTer SDRAM is only 16 bits wide
wire [31:0] sdram_dq;  
assign IO_sdram_dq = sdram_dq[15:0];
   
wire [3:0] sdram_dqm;  
assign O_sdram_dqm = sdram_dqm[1:0];

// ------ dual shock interface ------------

assign ds2_csn = 1'b1;   

// signals coming from dualshock2 p1
wire [4:0] ds1_p1;   

assign ds1_p1[0] = |ds1_buttons;
wire [3:0] ds1_buttons;   
   
dualshock2 ds2_p1 (
  .clk          ( clk32     ), // ds2 module actually expects 31.5 Mhz
  .rst          ( por       ),			   
  .vsync        ( !lcd_vs   ), // refresh once a screen
				   
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

  .leds_n ( leds_int_n ),
  .ws2812 ( ),

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

  // parallel port
  .parallel_strobe_oe ( ),
  .parallel_strobe_in ( 1'b1 ), 
  .parallel_strobe_out ( ), 
  .parallel_data_oe ( ),
  .parallel_data_in ( 8'h00 ),
  .parallel_data_out ( ),
  .parallel_busy ( 1'b1 ), 
		   
  // MIDI
  .midi_in  ( 1'b1  ),
  .midi_out ( ),
		   
  // SD card slot
  .sd_clk ( sd_clk ),
  .sd_cmd ( sd_cmd ), // MOSI
  .sd_dat ( sd_dat ), // 0: MISO

  .vreset ( vreset ),
  .vmode  ( vmode  ),
  .vwide  ( vwide  ),
	   
  // scandoubled digital video to be
  // used with lcds
  .lcd_clk  ( lcd_clk    ),
  .lcd_hs_n ( lcd_hs     ),
  .lcd_vs_n ( lcd_vs     ),
  .lcd_de   ( lcd_en     ),
  .lcd_r    ( lcd_r[7:2] ),
  .lcd_g    ( lcd_g[7:2] ),
  .lcd_b    ( lcd_b[7:2] ),

  // digital 16 bit audio output
  .audio ( audio )
);

assign lcd_r[1:0] = 2'b00;
assign lcd_g[1:0] = 2'b00;
assign lcd_b[1:0] = 2'b00;

video2hdmi video2hdmi (
    .clk      ( clk      ),       // clock in
    .clk_32   ( clk32    ),       // 32 Mhz clock out
    .pll_lock ( pll_lock_hdmi ),  // output clock is stable

    .vreset ( vreset ),
    .vmode ( vmode ),
    .vwide ( vwide ),

    .r( lcd_r[7:2] ),
    .g( lcd_g[7:2] ),
    .b( lcd_b[7:2] ),
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

