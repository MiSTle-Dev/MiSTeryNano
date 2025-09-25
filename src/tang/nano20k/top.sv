/*
    top.sv - atarist on tang nano 20k toplevel

    This top level implements the default variant for 20k with M0S
    Dock, DB9-Joystick and MIDI
*/ 

module top(
  input			clk,

  input			reset, // S2
  input			user, // S1

  output [5:0]	leds_n,
  output		ws2812,

  // interface to Tang onboard BL616 UART
  input			uart_rx,
  // output		uart_tx,
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

  // generic IO, used for mouse/joystick/...
  input [5:0]	io,

  // spare pins, used for 2nd joystick
  input [5:0]	spare,

  // interface to external BL616/M0S
  inout [4:0]	m0s,

  // MIDI
  input			midi_in,
  output		midi_out,
		   
  // SD card slot
  output		sd_clk,
  inout			sd_cmd, // MOSI
  inout [3:0]	sd_dat, // 0: MISO
	   
  // SPI connection to on-board BL616 for 3921 assemblies 
  // By default an external connection is used with a M0S Dock
  input			spi_sclk,// in 
  input			spi_csn, // in
  output		spi_dir, // out
  input			spi_dat, // in
  output		spi_irqn,// out

  // hdmi/tdms
  output		tmds_clk_n,
  output		tmds_clk_p,
  output [2:0]	tmds_d_n,
  output [2:0]	tmds_d_p
);

// connect onboard BL616 console to hw pins for an USB-UART adapter
// assign uart_tx = bl616_mon_rx;
assign bl616_mon_tx = uart_rx;

wire clk32;
wire pll_lock_hdmi;
wire por; 

// On the Tang Nano 20k we support two different MCU setups. Once uses the internal
// BL616 of the Tang Nano 20k and one uses an external M0S Dock. The MCU control signals
// of the MiSTeryNano have to be connected to both of them. This is simple for signals
// being sent out of the FPGA as these are simply connected to both MCU ports (even
// if no M0S may actually be connected at all). But for the input signals coming from
// the MCUs, the active one needs to be selected. This happens here.

// map output data onto both spi outputs
wire spi_io_dout;
wire spi_intn;

// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
// onboard connection to on-board BL616 only newer 3921 assemblies 
assign spi_dir = spi_io_dout;
assign m0s[4:0] = { spi_intn, 3'bzzz, spi_io_dout };
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
            spi_ext = 1'b1;
    end
end

// switch between internal SPI connected to the on-board bl616
// or to the external one possibly connected to a M0S Dock
wire spi_io_din = spi_ext?m0s[1]:spi_dat;
wire spi_io_ss = spi_ext?m0s[2]:spi_csn;
wire spi_io_clk = spi_ext?m0s[3]:spi_sclk;

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire        vwide;

wire [5:0]  r;
wire [5:0]  g;
wire [5:0]  b;

// sdram address can be up to 13 bits wide. tang nano 20k uses only 11
wire [12:0] sdram_addr;
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
  .io ( io ),

  // spare pins, used for 2nd DB9 joystick
  .spare ( spare ),

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
  .parallel_busy ( 1'b0 ), 
		   
  // MIDI
  .midi_in  ( midi_in  ),
  .midi_out ( midi_out ),
		   
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

