/* 
    misterynano.sv 

    This is the main MiSTeryNano core itself. It can be connected
    to different top levels exposing different signals.
*/

module misterynano (
  input			clk,
`ifdef EFINIX
  // with efinix, all plls are toplevel
  input         flash_clk,      // 100 MHz SPI flash clock
`endif
  input			reset, // S2
  input			user, // S1

  input			clk32,
  input			pll_lock_main,
  output		por, // power on-reset (! all PLL's locked)

  output [5:0]	leds_n,
  output		ws2812,

  // spi flash interface
  output		mspi_cs,
`ifdef EFINIX
  input			mspi_di_in,
  output		mspi_di_out,
  output		mspi_di_oe,
  input			mspi_do_in,
  output		mspi_do_out,
  output		mspi_do_oe,
`else
  output		mspi_clk,
  inout			mspi_di,
  inout			mspi_hold,
  inout			mspi_wp,
  inout			mspi_do,
`endif
					
  // "Magic" port names that the gowin compiler connects to the on-chip SDRAM
  output		sdram_clk,
  output		sdram_cke,
  output		sdram_cs_n, // chip select
  output		sdram_cas_n, // columns address select
  output		sdram_ras_n, // row address select
  output		sdram_wen_n, // write enable
`ifdef EFINIX
  input [15:0]	sdram_dq_in,
  output [15:0]	sdram_dq_out,
  output [15:0]	sdram_dq_oe,
  output [1:0]	sdram_dqm, // 16/2
`else
  inout [31:0]	sdram_dq, // up to 32 bit bidirectional data bus
  output [3:0]	sdram_dqm, // 32/4
`endif
  output [12:0]	sdram_addr, // up to 13 bit multiplexed address bus
  output [1:0]	sdram_ba, // two banks

  // MCU interface
  input			mcu_sclk,
  input			mcu_csn,
  output		mcu_miso, // from FPGA to MCU
  input			mcu_mosi, // from MCU to FPGA
  output		mcu_intn,

  // generic IO, used for mouse/joystick/...
  input [7:0]	io,

  // the parallel port of the ST only carries few signals
  output		parallel_strobe_oe,
  input			parallel_strobe_in, 
  output		parallel_strobe_out, 
  output		parallel_data_oe,
  input [7:0]	parallel_data_in,
  output [7:0]	parallel_data_out,
  input			parallel_busy, 
 					
  // MIDI
  input			midi_in,
  output		midi_out,
		   
  // SD card slot
  output		sd_clk,
`ifdef EFINIX
  input			sd_cmd_in, // MOSI
  output		sd_cmd_out,
  output		sd_cmd_oe,
  input [3:0]	sd_dat_in, // 0: MISO
  output [3:0]	sd_dat_out,
  output [3:0]	sd_dat_oe,
`else
  inout			sd_cmd, // MOSI
  inout [3:0]	sd_dat, // 0: MISO
`endif  
  
  // scandoubled digital video to be
  // used with lcds
  output		lcd_clk,
  output		lcd_hs_n,
  output		lcd_vs_n,
  output		lcd_de,
  output [5:0]	lcd_r,
  output [5:0]	lcd_g,
  output [5:0]	lcd_b,

  output		vreset,
  output [1:0]	vmode,
  output		vwide,

  // digital 16 bit audio output
  output [15:0]	audio [2]
);

/* TODO: Map addional joysticks to printerport for e.g. Gauntlet II
 DB9-A
 1 -> 6   DATA4
 2 -> 7   DATA5
 3 -> 8   DATA6
 4 -> 9   DATA7
 6 -> 11  BUSY

 DB9-B
 1 -> 2   DATA0
 2 -> 3   DATA1
 3 -> 4   DATA2
 4 -> 5   DATA3
 6 -> 1   STROBE
*/
    
// The Efinix T20 would not fit blitter and ACSI, so
// we disable them. On GW2AR-18 ACSI saves ~200 LUTs, blitter 
// saves ~2000 of them.
`ifdef EFINIX
 `define NO_ACSI
 `define NO_BLITTER
`endif
   
wire [5:0] leds;      // control leds with positive logic
assign leds_n = ~leds;

wire sys_resetn;

// connect to ws2812 led
wire [23:0] ws2812_color;
ws2812 ws2812_inst (
    .clk(clk32),
    .color(ws2812_color),
    .data(ws2812)
);

// system values are set by the external MCU (by the user via the OSD)
// and used to control the system in general
wire [1:0] system_leds;
wire [1:0] system_chipset;
wire       system_memory;
wire       system_video;
wire [1:0] system_reset;   // reset and coldboot flag
wire [1:0] system_scanlines;
wire [1:0] system_volume;
wire       system_wide_screen;
wire [1:0] system_floppy_wprot;
wire       system_cubase_en;
wire [1:0] system_port_mouse;
wire       system_port_joy;
wire       system_tos_slot;
   
/* -------------- clock generation --------------- */

`ifdef EFINIX
// in Efinix FPGAs the clock generation and PLLs are external.
assign por = !pll_lock_main;
`else
wire pll_lock_flash;   
wire flash_clk;      // 100.265 MHz SPI flash clock
flash_pll flash_pll (
        .clkout( flash_clk ),
        .clkoutp( mspi_clk ),   // shifted by -22.5/335.5 deg
        .lock(pll_lock_flash),
        .clkin(clk)
    );
wire pll_lock = pll_lock_main && pll_lock_flash;
assign por = !pll_lock;
`endif
    
/* -------------------- flash -------------------- */  

wire rom_n;
wire [23:1] rom_addr;
wire [15:0] rom_dout;

wire flash_ready;

flash flash (
    .clk(flash_clk),
    .resetn(!por),
    .ready(flash_ready),
    .busy(),

    // cpu expects ROM to start at $fc0000 and it is in fact is at $100000 in
    // cpu expects ROM to start at $fc0000 and it is in fact is at $100000 in
    // ST mode and at $140000 in STE mode. $180000 and $1c0000 are the secondary
    // slots which can be selected from the OSD
    .address( { 3'b001, system_tos_slot, (system_chipset >= 2'd2)?1'b1:1'b0, rom_addr[17:1] } ),
    .cs( !rom_n ),
    .dout(rom_dout),

    .mspi_cs(mspi_cs),
`ifdef EFINIX
    .mspi_di_in(mspi_di_in),
    .mspi_di_out(mspi_di_out),
    .mspi_di_oe(mspi_di_oe),
    .mspi_do_in(mspi_do_in),
    .mspi_do_out(mspi_do_out),
    .mspi_do_oe(mspi_do_oe)
`else
    .mspi_di(mspi_di),
    .mspi_do(mspi_do),
    .mspi_wp(mspi_wp),
    .mspi_hold(mspi_hold)
`endif
);

/* -------------------- RAM -------------------- */

wire ras_n, cash_n, casl_n;
wire [23:1] ram_a;
wire we_n;
wire [15:0] mdout;   // out to ram
wire [15:0] mdin;    // in from ram

wire ram_ready;
wire refresh;

// system_reset[1] indicates whether a coldboot is requested. This
// can either be triggered imlicitely by the user changing hardweare
// specs (ST vs. STE or RAM size) or explicitely via an OSD menu entry.
// A cold boot means that the ram contents becomoe invalid. We achieve this
// by scrambling the RAM address space a little bit on every rising edge
// of system_reset[1] 
reg [1:0] ram_scramble;
always @(posedge clk32) begin
    reg cb_D;
    cb_D <= system_reset[1];

    if(system_reset[1] && !cb_D)
        ram_scramble <= ram_scramble + 2'd1;
end

// RAM is scrambled by xor'ing adress lines 3 and 4 with the scramble bits
wire [22:1] ram_a_s = { ram_a[22:5], 
    ram_a[4:3] ^ ram_scramble, 
    ram_a[2:1] };

sdram sdram (
        .clk(clk32),
        .reset_n(!por),
        .ready(ram_ready),          // ram is done initialzing

        // interface to sdram chip
        .sd_clk(sdram_clk),      // clock
        .sd_cke(sdram_cke),      // clock enable
`ifdef EFINIX
        .sd_data_in(sdram_dq_in), // 16 bit bidirectional data bus
        .sd_data_out(sdram_dq_out), 
        .sd_data_oe(sdram_dq_oe),
`else
        .sd_data(sdram_dq),      // 16/32 bit bidirectional data bus
`endif        
        .sd_addr(sdram_addr),    // 11 bit multiplexed address bus
        .sd_dqm(sdram_dqm),      // two byte masks
        .sd_ba(sdram_ba),        // two banks
        .sd_cs(sdram_cs_n),      // a single chip select
        .sd_we(sdram_wen_n),     // write enable
        .sd_ras(sdram_ras_n),    // row address select
        .sd_cas(sdram_cas_n),    // columns address select

        // allow RAM access to the entire 8MB provided by the
        // Tang Nano 20k. It's up to the ST chipset to make use
        // of this
        .refresh(refresh),
        .din(mdout),                // data input from chipset/cpu
        .dout(mdin),
        .addr(ram_a_s),             // 22 bit word address
        .ds( { cash_n, casl_n } ),  // upper/lower data strobe
        .cs( !ras_n && !ram_a[23] ),// cpu/chipset requests read/write
        .we( !we_n )                // cpu/chipset requests write
);
   
// ST video signals to be sent through the scan doubler
wire st_hs_n, st_vs_n, st_bl_n, st_de;
wire [3:0] st_r;
wire [3:0] st_g;
wire [3:0] st_b;

wire [14:0] audio_l;
wire [14:0] audio_r;

// ----------------- SPI input parser ----------------------

wire       mcu_sys_strobe;
wire       mcu_hid_strobe;
wire       mcu_osd_strobe;
wire       mcu_sdc_strobe;
wire       mcu_start;

wire [7:0] mcu_data_out;  

wire [7:0] sys_data_out;  
wire [7:0] hid_data_out;  
wire [7:0] osd_data_out = 8'h55;
wire [7:0] sdc_data_out;
   
mcu_spi mcu (
        .clk(clk32),
        .reset(por),

        .spi_io_ss(mcu_csn),
        .spi_io_clk(mcu_sclk),
        .spi_io_din(mcu_mosi),
        .spi_io_dout(mcu_miso),

        .mcu_sys_strobe(mcu_sys_strobe),
        .mcu_hid_strobe(mcu_hid_strobe),
        .mcu_osd_strobe(mcu_osd_strobe),
        .mcu_sdc_strobe(mcu_sdc_strobe),
        .mcu_start(mcu_start),
        .mcu_dout(mcu_data_out),
        .mcu_sys_din(sys_data_out),
        .mcu_hid_din(hid_data_out),
        .mcu_osd_din(osd_data_out),
        .mcu_sdc_din(sdc_data_out)
        );
        
// ---- Mix HID mouse/joystick and DB9 joystick -----

// joy0 is usually used for the mouse, joy1 for the joystick. The
// joystick can either be driven from the external MCU or via FPGA IO pins
wire [5:0] hid_mouse;   // USB/HID mouse with four directions and two buttons
wire [7:0] hid_joy0;     // USB/HID joystick with four directions and four buttons
wire [7:0] hid_joy1;     // USB/HID joystick with four directions and four buttons

// external DB9 joystick port
wire [5:0] db9_atari = { !io[5], !io[0], !io[2], !io[1], !io[4], !io[3] };
wire [5:0] db9_amiga = { !io[5], !io[0], !io[3], !io[1], !io[4], !io[2] };

// external DB9 joystick port 2
wire [5:0] db9_joy2 = { !spare[5], !spare[0], !spare[2], !spare[1], !spare[4], !spare[3] };

// joy0 (port0) can be mouse or joystick. If mouse is connected it cannot work with parallel
// so mouse is deactivted if joystick button is detected in this case usb joy, but after adding 
// second db9 it can by added to joy0_joy. Mouse is activated when mouse button is added.
wire [5:0] joy0_mouse = ((system_port_mouse == 2'd0)?hid_mouse:
                  (system_port_mouse == 2'd1)? db9_atari:
                  (system_port_mouse == 2'd2) ? db9_amiga:
                  6'b000000); 
wire [5:0] joy0_joy = ((system_port_joy == 1'd1) ? hid_joy0[5:0] : {1'd0, hid_joy1[4:0]});

reg joy0_mouse_active;

always @(posedge clk32) begin
    if (por) begin
        joy0_mouse_active = 1'b1;
    end else begin
        if (!joy0_mouse_active && (joy0_mouse[5] || joy0_mouse[4])) begin
            joy0_mouse_active <= 1'b1;
        end else begin
            if (joy0_mouse_active && (joy0_joy[5] || joy0_joy[4])) begin
                joy0_mouse_active <= 1'b0;
            end
        end
    end
end

// any db9 mouse replaces usb mouse as mice will keep some signals
// permanently active and can thus not just be wired together
// add possibility to turn off mouse
wire [5:0] joy0 =  joy0_joy | ((joy0_mouse_active) ? joy0_mouse : 6'b000000);


// Joystick ports are just wired together and can be used in parallel
// DB9 is used for joystick, whenever the mouse is mapped to USB
wire [5:0] db9_joy = (system_port_mouse==2'd0)?db9_atari: 6'b000000;

wire [4:0] joy1 = ((system_port_joy == 1'd1) ? hid_joy1[4:0] | db9_joy2[4:0] : hid_joy0[4:0] ) | db9_joy[4:0];

// The keyboard matrix is maintained inside HID
wire [7:0] keyboard[14:0];

wire [14:0] keyboard_matrix_out;
wire [7:0] keyboard_matrix_in =
	      (!keyboard_matrix_out[0]?keyboard[0]:8'hff)&
	      (!keyboard_matrix_out[1]?keyboard[1]:8'hff)&
	      (!keyboard_matrix_out[2]?keyboard[2]:8'hff)&
	      (!keyboard_matrix_out[3]?keyboard[3]:8'hff)&
	      (!keyboard_matrix_out[4]?keyboard[4]:8'hff)&
	      (!keyboard_matrix_out[5]?keyboard[5]:8'hff)&
	      (!keyboard_matrix_out[6]?keyboard[6]:8'hff)&
	      (!keyboard_matrix_out[7]?keyboard[7]:8'hff)&
	      (!keyboard_matrix_out[8]?keyboard[8]:8'hff)&
	      (!keyboard_matrix_out[9]?keyboard[9]:8'hff)&
	      (!keyboard_matrix_out[10]?keyboard[10]:8'hff)&
	      (!keyboard_matrix_out[11]?keyboard[11]:8'hff)&
	      (!keyboard_matrix_out[12]?keyboard[12]:8'hff)&
	      (!keyboard_matrix_out[13]?keyboard[13]:8'hff)&
	      (!keyboard_matrix_out[14]?keyboard[14]:8'hff);

// decode SPI/MCU data received for human input devices (HID) and
// convert into ST compatible mouse and keyboard signals
wire [7:0] int_ack;
wire hid_int;
wire hid_iack = int_ack[1];

hid hid (
        .clk(clk32),
        .reset(por),

         // interface to receive user data from MCU (mouse, kbd, ...)
        .data_in_strobe(mcu_hid_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data_out),
        .data_out(hid_data_out),

        // input local db9 port events to be sent to MCU. Changes also trigger
        // an interrupt, so the MCU doesn't have to poll for joystick events
        .db9_port( db9_joy ),
        .irq( hid_int ),
        .iack( hid_iack ),

        .mouse(hid_mouse),
        .keyboard(keyboard),
        .joystick0(hid_joy1),
        .joystick1(hid_joy0)
         );   
         
wire sdc_int;
wire sdc_iack = int_ack[3];

wire [31:0] serial_status;
wire [7:0] serial_tx_available;
wire       serial_tx_strobe;
wire [7:0] serial_tx_data;
wire [7:0] serial_rx_available;
wire       serial_rx_strobe;
wire [7:0] serial_rx_data;

sysctrl sysctrl (
        .clk(clk32),
        .reset(por),

         // interface to send and receive generic system control
        .data_in_strobe(mcu_sys_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data_out),
        .data_out(sys_data_out),

		// port io (used to expose rs232)
	    .port_status(serial_status),
		.port_out_available(serial_tx_available),
        .port_out_strobe(serial_tx_strobe),
		.port_out_data(serial_tx_data),	 
		.port_in_available(serial_rx_available),
        .port_in_strobe(serial_rx_strobe),
		.port_in_data(serial_rx_data),	 
				 
        // values controlled by the OSD
`ifdef NO_BLITTER
        .system_chipset(),
        .system_cubase_en(),
`else
        .system_chipset(system_chipset),
        .system_cubase_en(system_cubase_en),
`endif
        .system_memory(system_memory),
        .system_video(system_video),
        .system_reset(system_reset),
        .system_scanlines(system_scanlines),
        .system_volume(system_volume),
        .system_wide_screen(system_wide_screen),
        .system_floppy_wprot(system_floppy_wprot),
        .system_port_mouse(system_port_mouse),
        .system_port_joy(system_port_joy),
        .system_tos_slot(system_tos_slot),
        
        .int_out_n(mcu_intn),
        .int_in( { 4'b0000, sdc_int, 1'b0, hid_int, 1'b0 }),
        .int_ack( int_ack ),

        .buttons( {user, reset} ),
        .leds(system_leds),
        .color(ws2812_color)
         );   
         
`ifdef NO_BLITTER
assign system_chipset = 2'd0;   // regular ST only
assign system_cubase_en = 1'b0; // no cubase dongle support   
`endif

// signals to wire the floppy controller to the sd card
wire [1:0]  sd_rd;   // fdc requests sector read
wire [1:0]  sd_wr;   //     -"-             write
wire [7:0]  sd_rd_data;
wire [7:0]  sd_wr_data;
wire [31:0] sd_lba;  
wire [8:0]  sd_byte_index;
wire	    sd_rd_byte_strobe;
wire	    sd_busy, sd_done;
wire [63:0] sd_img_size;
wire [3:0]  sd_img_mounted;
reg         sd_ready;

`ifndef NO_ACSI
// signals to wire ACSI to the SD card, some of these should be combined
// with the floppy iside atarist.v and ultimately inside dma.v 
wire [1:0] 	acsi_rd_req;
wire [1:0] 	acsi_wr_req;
wire [31:0] acsi_lba;
wire acsi_sd_done = sd_done;
wire acsi_sd_busy = sd_busy;
wire acsi_sd_rd_byte_strobe = sd_rd_byte_strobe;
wire [7:0] acsi_sd_rd_byte = sd_rd_data;
wire [7:0] acsi_sd_wr_byte;
wire [8:0] acsi_sd_byte_addr = sd_byte_index;
`endif
   
atarist atarist (
    .clk_32(clk32),
    .resb(!system_reset[0] && !reset && !por && ram_ready && flash_ready && sd_ready),       // user reset button
    .porb(!por),

    // video output
    .hsync_n(st_hs_n),
    .vsync_n(st_vs_n),
    .blank_n(st_bl_n),
    .de(st_de),
    .r(st_r),
    .g(st_g),
    .b(st_b),
    .mono_detect(!system_video),    // mono=0, color=1

    .keyboard_matrix_out(keyboard_matrix_out),
    .keyboard_matrix_in(keyboard_matrix_in),
	.joy0( joy0 ),
	.joy1( joy1 ),

    // Sound output
    .audio_mix_l( audio_l ),
    .audio_mix_r( audio_r ),

    // MIDI UART
    .midi_rx(midi_in),
    .midi_tx(midi_out),

    // serial/rs232
	.serial_status       ( serial_status       ),
	.serial_tx_available ( serial_tx_available ),
	.serial_tx_strobe    ( serial_tx_strobe    ),
	.serial_tx_data      ( serial_tx_data      ),
	.serial_rx_available ( serial_rx_available ),
	.serial_rx_strobe    ( serial_rx_strobe    ),
	.serial_rx_data      ( serial_rx_data      ),

	// parallel port
    .parallel_strobe_oe  ( parallel_strobe_oe  ),
    .parallel_strobe_in  ( parallel_strobe_in  ), 
    .parallel_strobe_out ( parallel_strobe_out ), 
    .parallel_data_oe    ( parallel_data_oe    ),
    .parallel_data_in    ( parallel_data_in    ),
    .parallel_data_out   ( parallel_data_out   ),
    .parallel_busy       ( parallel_busy       ),
				 
    // interface to receive image file size/presence
    .sd_img_mounted ( sd_img_mounted ),
    .sd_img_size    ( sd_img_size ),

    // ACSI disk/sd card interface
`ifdef NO_ACSI
	.acsi_rd_req( ),
	.acsi_wr_req( ),
	.acsi_sd_lba( ),
 	.acsi_sd_done(1'b0),
 	.acsi_sd_busy(1'b0),
	.acsi_sd_rd_byte_strobe(1'b0),
	.acsi_sd_rd_byte(8'h00),
	.acsi_sd_wr_byte(),
	.acsi_sd_byte_addr(9'h000),
`else
	.acsi_rd_req(acsi_rd_req),
	.acsi_wr_req(acsi_wr_req),
	.acsi_sd_lba(acsi_lba),
 	.acsi_sd_done(acsi_sd_done),
 	.acsi_sd_busy(acsi_sd_busy),
	.acsi_sd_rd_byte_strobe(acsi_sd_rd_byte_strobe),
	.acsi_sd_rd_byte(acsi_sd_rd_byte),
	.acsi_sd_wr_byte(acsi_sd_wr_byte),
	.acsi_sd_byte_addr(acsi_sd_byte_addr),
`endif
				 
    // floppy/acsi sd card interface
	.sd_lba         ( sd_lba ),
	.sd_rd          ( sd_rd ),
	.sd_wr          ( sd_wr ),
	.sd_ack         ( sd_busy ),
	.sd_buff_addr   ( sd_byte_index ),
	.sd_dout        ( sd_rd_data ),
	.sd_din         ( sd_wr_data ),
    .sd_dout_strobe ( sd_rd_byte_strobe ),

    // interface to ROM
    .rom_n(rom_n),
    .rom_addr(rom_addr),
    .rom_data_out(rom_dout),

    // external configurations
    .blitter_en(system_chipset >= 2'd1),    // MegaST (1) or STE (2)
    .ste(system_chipset >= 2'd2),           // STE (2)
    .enable_extra_ram(system_memory),       // enable extra ram
    .floppy_protected(system_floppy_wprot), // floppy write protection
    .cubase_en(system_cubase_en),           // enable cubase dongles

    // interface to sdram
    .ram_ras_n(ras_n),
    .ram_cash_n(cash_n),
    .ram_casl_n(casl_n),
    .ram_ref(refresh),
    .ram_addr(ram_a),
    .ram_we_n(we_n),
    .ram_data_in(mdout),
    .ram_data_out(mdin),

    .leds(leds[3:0])     // HDD 1:0 / FDC 1:0
  );
  
/* ------------ expand audio to 16 bits and apply volume adjustment ------------ */
wire [15:0] audio16_l = { audio_l[14], audio_l };
wire [15:0] audio16_r = { audio_r[14], audio_r };

// scale audio for valume by signed division
wire [15:0] audio_vol_l = 
    (system_volume == 2'd0)?16'd0:
    (system_volume == 2'd1)?{ {2{audio16_l[15]}}, audio16_l[15:2] }:
    (system_volume == 2'd2)?{ audio16_l[15], audio16_l[15:1] }:
    audio16_l;

wire [15:0] audio_vol_r = 
    (system_volume == 2'd0)?16'd0:
    (system_volume == 2'd1)?{ {2{audio16_r[15]}}, audio16_r[15:2] }:
    (system_volume == 2'd2)?{ audio16_r[15], audio16_r[15:1] }:
    audio16_r;

// expose this audio to the toplevel to e.g. feed it into a dac
assign audio[0] = audio_vol_l;
assign audio[1] = audio_vol_r;

assign vwide = system_wide_screen;

video video (
	     .clk_pixel(clk32),
         .por(por),

         .mcu_start(mcu_start),
         .mcu_osd_strobe(mcu_osd_strobe),
         .mcu_data(mcu_data_out),

         // values that can be configure by the user via osd
         .system_scanlines(system_scanlines),
         .system_wide_screen(system_wide_screen),

         // video control signal output
         .vreset ( vreset ),    // reached top/left pixel
         .vmode ( vmode ),      // atari st video mode

	     .hs_in_n(st_hs_n),
	     .vs_in_n(st_vs_n),
	     .de_in(st_de),
	     .r_in(st_r),
	     .g_in(st_g),
	     .b_in(st_b),

         // volume adjusted 16 bit audio
         .audio_l( audio_vol_l ),
         .audio_r( audio_vol_r ),

         // digital output for lcd
         .lcd_clk(lcd_clk),
         .lcd_hs_n(lcd_hs_n),
         .lcd_vs_n(lcd_vs_n),
         .lcd_de(lcd_de),
         .lcd_r(lcd_r),
         .lcd_g(lcd_g),
         .lcd_b(lcd_b)
	     );

// -------------------------- SD card -------------------------------

assign leds[5:4] = system_leds[1:0];

// Give MCU some time to open a default disk image before booting the core
// image_size != 0 means card is initialized. Wait up to 2 seconds for this before
// booting the ST
reg [31:0] sd_wait;
always @(posedge clk32) begin
    if(por) begin
        sd_wait <= 32'd0;
        sd_ready <= 1'b0;
    end else begin
        if(!sd_ready) begin
            // ready once image size is != 0
            if(sd_img_size != 64'd0)
                sd_ready <= 1'b1;

            // or after 2 seconds
            if(sd_wait < 32'd64000000)
                sd_wait <= sd_wait + 32'd1;
            else
                sd_ready <= 1'b1;
        end
    end
end

`ifndef NO_ACSI
// differentiate between floppy and acsi requests
wire      is_acsi = (acsi_rd_req != 0) ||  (acsi_wr_req != 0) || is_acsi_D;   
reg 	  is_acsi_D;
   
always @(posedge clk32) begin
   // ACSI requests IO -> save state
   if(acsi_rd_req || acsi_wr_req)
     is_acsi_D <= 1'b1;
   
   // FDC requests IO 
   if(sd_rd || sd_wr)
     is_acsi_D <= 1'b0;
end
`endif
   
sd_card #(
    .CLK_DIV(3'd1)                    // for 32 Mhz clock
) sd_card (
    .rstn(!por),                     // rstn active-low, 1:working, 0:reset
    .clk(clk32),                     // clock
  
    // SD card signals
    .sdclk(sd_clk),
`ifdef EFINIX
    .sdcmd_in(sd_cmd_in),
    .sdcmd_out(sd_cmd_out),
    .sdcmd_oe(sd_cmd_oe),
    .sddat_in(sd_dat_in),
    .sddat_out(sd_dat_out),
    .sddat_oe(sd_dat_oe),
`else
    .sdcmd(sd_cmd),
    .sddat(sd_dat),
`endif
    
    // mcu interface
    .data_strobe(mcu_sdc_strobe),
    .data_start(mcu_start),
    .data_in(mcu_data_out),
    .data_out(sdc_data_out),

    // output file/image information. Image size is e.g. used by fdc to 
    // translate between sector/track/side and lba sector
    .image_size(sd_img_size),           // length of image file
    .image_mounted(sd_img_mounted),

    // interrupt to signal communication request
    .irq(sdc_int),
    .iack(sdc_iack),

`ifdef NO_ACSI
	// on t20 only floppy is being implemented
    .rstart( { 2'b00, sd_rd } ), 
    .wstart( { 2'b00, sd_wr } ),
    .rsector( sd_lba ),
    .inbyte(sd_wr_data),
`else
    // user read sector command interface (sync with clk32)
    .rstart( { acsi_rd_req, sd_rd} ), 
    .wstart( { acsi_wr_req, sd_wr } ), 
    .rsector( is_acsi?acsi_lba:sd_lba),
    .inbyte(is_acsi?acsi_sd_wr_byte:sd_wr_data),
`endif

    .rbusy(sd_busy),
    .rdone(sd_done),
		   
    // sector data output interface (sync with clk32)
    .outen(sd_rd_byte_strobe), // when outen=1, a byte of sector content is read out from outbyte
    .outaddr(sd_byte_index),   // outaddr from 0 to 511, because the sector size is 512
    .outbyte(sd_rd_data)       // a byte of sector content
);

endmodule

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:

