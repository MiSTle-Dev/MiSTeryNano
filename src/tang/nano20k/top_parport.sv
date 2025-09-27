/*
    top.sv - atarist on tang nano 20k toplevel

    This top level implements a variant with M0S Dock 
    support and the parallel (printer) port exposed.
 
    This is e.g. used with the fischertechnik computing
    interface. Since the FPGA supports at most 3.3V IO
    additional level shifters are needed when connecting
    with 5V peripherals.
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

  // IO used for parallel port
  inout			pp_strobe,
  inout [7:0]	pp_data,
  input			pp_busy,
		   
  // interface to external BL616/M0S
  inout [5:0]	m0s,

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
assign m0s[5:0] = { 1'bz, spi_intn, 3'bzzz, spi_io_dout };
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

// drive parallel port signals as required
wire		pp_strobe_oe;
wire		pp_strobe_in = pp_strobe;   
wire		pp_strobe_out;
assign pp_strobe = pp_strobe_oe?pp_strobe_out:1'bz;
   
wire		pp_data_oe;   
wire [7:0]  pp_data_in = pp_data;  
wire [7:0]  pp_data_out;
assign pp_data = pp_data_oe?pp_data_out:8'bzzzzzzzz;
  
// sdram address can be up to 13 bits wide. tang nano 20k uses only 11
wire [13:0] sdram_addr;
assign O_sdram_addr = sdram_addr[10:0];

misterynano  #(.EXTERNAL_PARPORT(1)) misterynano (
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
  .io    ( 6'b111111 ),
  .spare ( 6'b111111 ),

  // mcu interface
  .mcu_sclk ( spi_io_clk  ),
  .mcu_csn  ( spi_io_ss   ),
  .mcu_miso ( spi_io_dout ), // from FPGA to MCU
  .mcu_mosi ( spi_io_din  ), // from MCU to FPGA
  .mcu_intn ( spi_intn    ),

  // MIDI is not implemented
						 
  // parallel port
  .parallel_strobe_oe ( pp_strobe_oe ),
  .parallel_strobe_in ( pp_strobe_in ), 
  .parallel_strobe_out ( pp_strobe_out ), 
  .parallel_data_oe ( pp_data_oe ),
  .parallel_data_in ( pp_data_in ),
  .parallel_data_out ( pp_data_out ),
  .parallel_busy ( pp_busy ), 
		   
  // SD card slot
  .sd_clk ( sd_clk ),
  .sd_cmd ( sd_cmd ), // MOSI
  .sd_dat ( sd_dat ), // 0: MISO

  .vreset ( vreset ),
  .vmode  ( vmode  ),
  .vwide  ( vwide  ),
	   
  // scandoubled digital video to be
  // used with lcds. For HDMI only the color signals are
  // being used. The timing is (also) generated inside hdmi
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

