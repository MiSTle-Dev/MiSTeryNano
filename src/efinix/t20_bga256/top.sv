//
// MiSTeryNano toplevel for Efinix T20 BGA256 dev board
//

module top (
    input	       clk,
    output [7:0]       leds,
    input [2:0]	       buttons,

    // Efinix PLLs are external from the logic
    input	       pll_lock,
    input	       clk_pixel_x5,
    input	       clk_pixel, 
    input	       flash_clk, // 100 MHz SPI flash clock

    // SDRAM interface
    input [15:0]       SDRAM_DQ_IN,
    output [15:0]      SDRAM_DQ_OUT,
    output [15:0]      SDRAM_DQ_OE,
    output [12:0]      SDRAM_A,
    output [1:0]       SDRAM_BA,
    output	       SDRAM_UDQM,
    output	       SDRAM_LDQM,
    output	       SDRAM_CLK,
    output	       SDRAM_CKE,
    output	       SDRAM_nCS,
    output	       SDRAM_nWE,
    output	       SDRAM_nRAS,
    output	       SDRAM_nCAS,

    // connection to fpga boot flash
    output	       mspi_clk,
    output	       mspi_cs,
    input	       mspi_di_in,
    output	       mspi_di_out,
    output	       mspi_di_oe,
    input	       mspi_do_in,
    output	       mspi_do_out,
    output	       mspi_do_oe,

    // SD card slot
    output         sd_clk,
    input          sd_cmd_in,  // MOSI
    output         sd_cmd_out,
    output         sd_cmd_oe,
    input [3:0]    sd_dat_in,  // 0: MISO
    output [3:0]   sd_dat_out,
    output [3:0]   sd_dat_oe,

    // SPI connection FPGA companion
    input	       spi_clk,
    input	       spi_ss,
    output	       spi_dout,
    input	       spi_din,
    output	       spi_intn,

    // for now we just use a hand-crafted TMDS
    output logic [7:0] tmds
);

`define PIXEL_CLOCK 32000000

wire clk32 = clk_pixel;

// route mspi clock from pll to flash chip
assign mspi_clk = flash_clk;

wire [5:0] leds_n;
assign leds = { 2'b11, leds_n };

wire [15:0] audio [2];
wire        vreset;
wire [1:0]  vmode;
wire        vwide;

wire [5:0]  r;
wire [5:0]  g;
wire [5:0]  b;

wire	    por;   

misterynano misterynano (
  .clk   ( clk ),           // 50MHz clock used e.g. for the flash pll
  
`ifdef EFINIX
  // efinix places plls outside the design, thus we route the 
  // flash related clock signals from the top
  .flash_clk      ( flash_clk ),      // 100 MHz SPI flash clock
`endif
    
  .reset ( !buttons[0] ),
  .user  ( !buttons[1] ),

  // clock and power on reset from system
  .clk32 ( clk32 ),         // 32 Mhz system clock input
  .pll_lock_main( pll_lock ),
  .por   ( por ),           // output. True while not all PLLs locked

  .leds_n ( leds_n ),
  .ws2812 ( ws2812 ),

  // spi flash interface
  .mspi_cs      ( mspi_cs   ),
  .mspi_di_in   ( mspi_di_in   ),
  .mspi_di_out  ( mspi_di_out   ),
  .mspi_di_oe   ( mspi_di_oe   ),
  .mspi_do_in   ( mspi_do_in   ),
  .mspi_do_out  ( mspi_do_out   ),
  .mspi_do_oe   ( mspi_do_oe   ),
			 
  // SDRAM
  .sdram_clk   ( SDRAM_CLK      ),
  .sdram_cke   ( SDRAM_CKE      ),
  .sdram_cs_n  ( SDRAM_nCS      ), // chip select
  .sdram_cas_n ( SDRAM_nCAS     ), // columns address select
  .sdram_ras_n ( SDRAM_nRAS     ), // row address select
  .sdram_wen_n ( SDRAM_nWE      ), // write enable
  .sdram_dq_in ( SDRAM_DQ_IN    ), // 16 bit bidirectional data bus
  .sdram_dq_out( SDRAM_DQ_OUT   ),
  .sdram_dq_oe ( SDRAM_DQ_OE    ),
  .sdram_addr  ( SDRAM_A        ), // 13 bit multiplexed address bus
  .sdram_ba    ( SDRAM_BA       ), // four banks
  .sdram_dqm   ( { SDRAM_UDQM, SDRAM_LDQM } ), // 16/2

  // generic IO, used for mouse/joystick/...
  .io ( 8'hff ),

  // mcu interface
  .mcu_sclk ( spi_clk  ),
  .mcu_csn  ( spi_ss   ),
  .mcu_miso ( spi_dout ), // from FPGA to MCU
  .mcu_mosi ( spi_din  ), // from MCU to FPGA
  .mcu_intn ( spi_intn    ),

  // parallel port and MIDI are not implemented
                   
  // SD card slot
  .sd_clk     ( sd_clk     ),
  .sd_cmd_in  ( sd_cmd_in  ), // MOSI
  .sd_cmd_out ( sd_cmd_out ),
  .sd_cmd_oe  ( sd_cmd_oe  ),
  .sd_dat_in  ( sd_dat_in  ), // 0: MISO
  .sd_dat_out ( sd_dat_out ),
  .sd_dat_oe  ( sd_dat_oe  ),

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

// generate 48khz audio clock
reg clk_audio;
reg [8:0] aclk_cnt;
always @(posedge clk_pixel) begin
    if(aclk_cnt < `PIXEL_CLOCK / 48000 / 2 -1)
        aclk_cnt <= aclk_cnt + 9'd1;
    else begin
        aclk_cnt <= 9'd0;
        clk_audio <= ~clk_audio;
    end
end
   
hdmi #(
    .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
    .VENDOR_NAME( { "MiSTle", 16'd0} ),
    .PRODUCT_DESCRIPTION( {"Atari ST", 64'd0} )
) hdmi(
  .clk_pixel_x5(clk_pixel_x5),
  .clk_pixel(clk_pixel),
  .clk_audio(clk_audio),
  .audio_sample_word( audio ),       
  .tmds_clock(tmds[1:0]),
  .tmds(tmds[7:2]),

  // video input
  .stmode( vmode ),    // current video mode NTSC/PAL/MONO
  .wide( vwide ),      // adopt to wide screen video
  .reset( vreset ),    // signal to synchronize HDMI

  // Atari STE outputs 4 bits per color. Scandoubler outputs 6 bits (to be
  // able to implement dark scanlines) and HDMI expects 8 bits per color
  .rgb( { r, 2'b00,  g, 2'b00, b, 2'b00 } )
);

endmodule
