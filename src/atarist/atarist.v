/********************************************/
/*       Atari ST/STe/Mega STe core         */
/********************************************/

module atarist (
	// System clocks / reset / settings
	input wire 		   clk_32,
	input wire 		   porb,
	input wire 		   resb,

	// Video output
	input wire 		   mono_detect, // low for monochrome
	output wire [3:0]  r,
	output wire [3:0]  g,
	output wire [3:0]  b,
	output wire 	   hsync_n,
	output wire 	   vsync_n,
	output wire 	   de,
	output wire 	   blank_n,

    // keyboard, mouse and joystick(s)
	output wire [14:0] keyboard_matrix_out,
	input wire [7:0]   keyboard_matrix_in,
	input wire [5:0]   joy0,
	input wire [4:0]   joy1,

	// Sound output
	output wire [14:0] audio_mix_l,
	output wire [14:0] audio_mix_r,

    // floppy disk/sd card interface
	output [31:0] 	   sd_lba,
	output [1:0] 	   sd_rd,
	output [1:0] 	   sd_wr,
	input 			   sd_ack,
	input [8:0] 	   sd_buff_addr,
	input [7:0] 	   sd_dout,
	output [7:0] 	   sd_din,
	input 			   sd_dout_strobe,

	// generic sd card services
	input [3:0] 	   sd_img_mounted,
	input [63:0] 	   sd_img_size,

    // ACSI disk/sd card interface
	output [1:0] 	   acsi_rd_req,
	output [1:0] 	   acsi_wr_req,
	output [31:0] 	   acsi_sd_lba,
 	input 			   acsi_sd_done,
 	input 			   acsi_sd_busy,
	input 			   acsi_sd_rd_byte_strobe,
	input [7:0] 	   acsi_sd_rd_byte,
	output [7:0] 	   acsi_sd_wr_byte,
	input [8:0] 	   acsi_sd_byte_addr,
					 
    // serial/rs232 to MCU
	output [31:0]      serial_status,
	output [7:0]       serial_tx_available,
	input              serial_tx_strobe,
	output [7:0]       serial_tx_data,
	output [7:0]       serial_rx_available,
	input              serial_rx_strobe,
	input [7:0]        serial_rx_data,
				
	// MIDI UART
	input wire 		   midi_rx,
	output wire 	   midi_tx,

	// printer signals
	output 			   parallel_strobe_oe,
	input 			   parallel_strobe_in, 
	output 			   parallel_strobe_out, 
	output 			   parallel_data_oe,
	input [7:0] 	   parallel_data_in,
	output [7:0] 	   parallel_data_out,
	input 			   parallel_busy, 

    // enable STE and extra 8MB ram
    input wire 		   ste,
    input wire 		   enable_extra_ram,
    input wire 		   blitter_en,
    input [1:0] 	   floppy_protected, // floppy A/B write protect
	input 			   cubase_en,
				
	// DRAM interface
	output wire 	   ram_ras_n,
	output wire 	   ram_cash_n,
	output wire 	   ram_casl_n,
	output wire 	   ram_we_n,
	output wire 	   ram_ref,
	output wire [23:1] ram_addr,
	output wire [15:0] ram_data_in,
	input wire [15:0]  ram_data_out,

	// TOS ROM interface
	output wire 	   rom_n, 
	output wire [23:1] rom_addr,
	input wire [15:0]  rom_data_out,
				
	// export all LEDs
	output wire [3:0]  leds
);

// registered reset signals
reg         reset;
reg         peripheral_reset;
reg         mcu_reset_n = 1'b1;
reg   [6:0] reset_cnt = 7'h7f;
reg         cpu_reset_n_d;
wire        ext_reset = !resb;

// rom cartridge related signals
wire 	    cart_n;   
wire [15:0] cart_data_out;
   
always @(posedge clk_32) begin

    cpu_reset_n_d <= cpu_reset_n_o;

	reset <= reset_cnt != 0;

	if (reset_cnt != 0) reset_cnt <= reset_cnt - 1'd1;
	if (ext_reset) reset_cnt <= 7'h7f;

	peripheral_reset <= reset | ~cpu_reset_n_o;

	// don't keep the GSTMCU in reset, because its signals are needed for the SDRAM controller
	if (reset_cnt == 10) mcu_reset_n <= 0;
	else if (reset_cnt < 8) mcu_reset_n <= 1;
	if (~cpu_reset_n_o & cpu_reset_n_d) mcu_reset_n <= 0;
end

// generate 2.4576MHz MFP clock
reg [31:0]  clk_cnt_mfp;
reg 	    clk_mfp_en;

localparam SYSTEM_CLOCK = 32'd32_084_988;
localparam MFP_CLOCK    =  32'd2_457_600;

always @(posedge clk_32) begin
    if(!porb) begin
        clk_cnt_mfp <= 32'd0;
	    clk_mfp_en <= 1'b0;
    end else begin
	    clk_mfp_en <= 1'b0;
	   
        if(clk_cnt_mfp < SYSTEM_CLOCK)
            clk_cnt_mfp <= clk_cnt_mfp + MFP_CLOCK;
        else begin
            clk_cnt_mfp <= clk_cnt_mfp - SYSTEM_CLOCK + MFP_CLOCK;
            clk_mfp_en <= 1'b1;
        end
    end   
end
   
// MCU signals

wire        mhz4, mhz4_en, clk16;
wire        mcu_dtack_n;
wire        ras0_n, ras1_n;
wire        cas0h_n, cas0l_n, cas1h_n, cas1l_n;
assign      ram_cash_n = cas0h_n & cas1h_n;
assign      ram_casl_n = cas0l_n & cas1l_n;   
wire        mfpint_n, mfpcs_n, mfpiack_n;
wire        sndir, sndcs;
wire        n6850, fcs_n;
wire        rtccs_n, rtcrd_n, rtcwr_n;
wire        sint;
wire [15:0] mcu_dout;
wire        mcu_oe_l, mcu_oe_h;
assign      ram_ras_n = ras0_n & ras1_n;
wire        button_n, joywe_n, joyrl_n, joywl, joyrh_n;

// dma
wire        rdy_o, rdy_i, mcu_bg_n, mcu_br_n, mcu_bgack_n;

// for other peripherals
wire        iodevice = ~as_n & fc2 & (fc0 ^ fc1) & mbus_a[23:16] == 8'hff;

// CPU signals
wire        mhz8, mhz8_en1, mhz8_en2;
wire        berr_n;
wire        ipl0_n, ipl1_n, ipl2_n;
wire        cpu_fc0, cpu_fc1, cpu_fc2;
wire        cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n, vma_n, vpa_n, cpu_E;
wire        cpu_reset_n_o;
wire [15:0] cpu_din, cpu_dout;
wire [23:1] cpu_a;

// Blitter signals needed beforehand
wire        blitter_br_n;
wire        blitter_bgack_n;
wire        blitter_bg_n;
wire        blitter_sel;
wire [15:0] blitter_data_out;

wire [15:0] dma_data_out;

assign rom_addr = mbus_a; // cpu_a;
   
wire [7:0] snd_data_out;  
   
assign      cpu_din = 
              ((~fcs_n & rw) ? dma_data_out : 16'hffff) &
              (blitter_sel ? blitter_data_out : 16'hffff) &
              (rdat_n ? 16'hffff : shifter_dout) &
              {8'hff, (mfpcs_n & mfpiack_n) ? 8'hff : mfp_data_out} &
			  (cart_n ? 16'hffff : cart_data_out ) &
              (rom_n ? 16'hffff : rom_data_out) &
              {(n6850 & rw) ? (mbus_a[2] ? midi_acia_data_out : kbd_acia_data_out) : 8'hff, 8'hff} &
              {snd_data_oe_l ? 8'hff : snd_data_out, 8'hff} &
// STE only       {12'hfff, button_n ? 4'hf : ste_buttons} &
// STE only       {joyrh_n ? 8'hff : ste_joy_in[15:8], joyrl_n ? 8'hff : ste_joy_in[7:0]} &
              {12'hfff, (rtccs_n & rw) ? 4'hf : rtc_data_out} &
              {mcu_oe_h ? mcu_dout[15:8] : 8'hff, mcu_oe_l ? mcu_dout[7:0] : 8'hff};

// Shifter signals
wire        cmpcs_n, latch, rdat_n, wdat_n, dcyc_n, sreq, sload_n, mono;
wire [15:0] shifter_dout;
wire [ 7:0] dma_snd_l, dma_snd_r;

// combined bus signals
wire        fc0 = blitter_has_bus ? blitter_fc0 : cpu_fc0;
wire        fc1 = blitter_has_bus ? blitter_fc1 : cpu_fc1;
wire        fc2 = blitter_has_bus ? blitter_fc2 : cpu_fc2;
wire        as_n = blitter_has_bus ? blitter_as_n : cpu_as_n;
wire        rw = blitter_has_bus ? blitter_rw_n : cpu_rw;
wire        uds_n = blitter_has_bus ? blitter_ds_n : cpu_uds_n;
wire        lds_n = blitter_has_bus ? blitter_ds_n : cpu_lds_n;
wire [23:1] mbus_a = blitter_has_bus ? blitter_addr : cpu_a;
// dout from the current bus master - TODO: merge with cpu_din after adding output enables to GSTMCU
wire [15:0] mbus_dout = !rdat_n ? shifter_dout :
                        !rom_n   ? rom_data_out :
                        blitter_sel ? blitter_data_out :
                        ~rdy_i ? dma_data_out :
                        cpu_dout;

wire        dtack_n = mcu_dtack_n_adj & ~mfp_dtack & blitter_dtack_n;

/* ------------------------------------------------------------------------------ */
/* ------------------------------ GSTMCU + Shifter ------------------------------ */
/* ------------------------------------------------------------------------------ */

// auto detect TOS ROM location at end of rom cycle (rising edge of rom_n)
// analyze the reset vector stored at address 4
reg	    rom_nD;
reg	    rom192k;
	    
always @(posedge clk_32) begin
   if( !porb ) begin
      rom192k <= 1'b1;
      rom_nD <= 1'b1;
   end else begin  
      rom_nD <= rom_n;
      if(rom_n == 1'b1 && rom_nD == 1'b0)
	if(rom_addr == 23'd2)
	  rom192k <= rom_data_out == 16'h00fc;
   end
end
   
gstmcu gstmcu (
	.clk32      ( clk_32 ),
	.resb       ( mcu_reset_n ),
	.porb       ( porb ),
	.FC0        ( fc0 ),
	.FC1        ( fc1 ),
	.FC2        ( fc2 ),
	.AS_N       ( as_n ),
	.RW         ( rw ),
	.UDS_N      ( uds_n ),
	.LDS_N      ( lds_n ),
	.VMA_N      ( vma_n ),
	.MFPINT_N   ( mfpint_n ),
	.A          ( mbus_a ), // from CPU bus
	.ADDR       ( ram_addr ),  // to RAM
	// DIN - only interested in sources which can be bus masters (+shifter) - to avoid long combinatorial paths
	.DIN        ( ~rdy_i ? dma_data_out : blitter_sel ? blitter_data_out : !rdat_n  ? shifter_dout : cpu_dout ),
	.DOUT       ( mcu_dout ),
	.OE_L       ( mcu_oe_l ),
	.OE_H       ( mcu_oe_h ),
	.CLK_O      ( clk16 ),
	.MHZ8       ( mhz8 ),
	.MHZ8_EN1   ( mhz8_en1 ),
	.MHZ8_EN2   ( mhz8_en2 ),
	.MHZ4       ( mhz4 ),
	.MHZ4_EN    ( mhz4_en ),
	.RDY_N_I    ( rdy_o ),
	.RDY_N_O    ( rdy_i ),
	.BG_N       ( mcu_bg_n ),
	.BR_N_I     ( blitter_br_n ),
	.BR_N_O     ( mcu_br_n ),
	.BGACK_N_I  ( 1'b1 ),
	.BGACK_N_O  ( mcu_bgack_n ),
	.BERR_N     ( berr_n ),
	.IPL0_N     ( ipl0_n ),
	.IPL1_N     ( ipl1_n ),
	.IPL2_N     ( ipl2_n ),
	.DTACK_N_I  ( dtack_n ),
	.DTACK_N_O  ( mcu_dtack_n ),
	.IACK_N     ( mfpiack_n),
	.ROM0_N     ( ),           // unused E8xxxx-EBxxxx
	.ROM1_N     ( ),           // unused E4xxxx-E7xxxx
	.ROM2_N     ( rom_n ),     // TOS rom E0xxxx/FCxxxx
	.ROM3_N     ( cart_n ),    // cartridge FBxxxx
	.ROM4_N     ( ),           // cartridge FAxxxx
	.ROM5_N     ( ),           // unused D4xxxx-D7xxxx
	.ROM6_N     ( ),           // unused D0xxxx-D3xxxx
	.ROMP_N     ( ),           // unused FE0xxx-FE1xxx
	.RAM_N      ( ),
	.RAS0_N     ( ras0_n ),
	.RAS1_N     ( ras1_n ),
	.CAS0L_N    ( cas0l_n ),
	.CAS0H_N    ( cas0h_n ),
	.CAS1L_N    ( cas1l_n ),
	.CAS1H_N    ( cas1h_n ),
	.RAM_LDS    ( ),
	.RAM_UDS    ( ),
	.REF        ( ram_ref ),
	.VPA_N      ( vpa_n ),
	.MFPCS_N    ( mfpcs_n ),
	.SNDIR      ( sndir ),
	.SNDCS      ( sndcs ),
	.N6850      ( n6850 ),
	.FCS_N      ( fcs_n ),
	.RTCCS_N    ( rtccs_n ),
	.RTCRD_N    ( rtcrd_n ),
	.RTCWR_N    ( rtcwr_n ),
	.LATCH      ( latch ),
	.HSYNC_N    ( hsync_n ),
	.VSYNC_N    ( vsync_n ),
	.DE         ( de ),
	.BLANK_N    ( blank_n ),
	.RDAT_N     ( rdat_n ),
	.WE_N       ( ram_we_n ),
	.WDAT_N     ( wdat_n ),
	.CMPCS_N    ( cmpcs_n ),
	.DCYC_N     ( dcyc_n ),
	.SREQ       ( sreq),
	.SLOAD_N    ( sload_n),
	.SINT       ( sint ),

	.BUTTON_N   ( button_n ),
	.JOYWE_N    ( joywe_n  ),
	.JOYRL_N    ( joyrl_n  ),
	.JOYWL      ( joywl    ),
	.JOYRH_N    ( joyrh_n  ),

	.st            ( ~ste ),
	.extra_ram     ( enable_extra_ram ),     // Tang Nano might offer 8MB
	.tos192k       ( rom192k ), 
	.turbo         ( 1'b0 ),     // no turbo
	.viking_at_c0  ( 1'b0 ),
	.viking_at_e8  ( 1'b0 ),
	.bus_cycle     ( )
);

gstshifter gstshifter (
	.clk32      ( clk_32 ),
	.ste        ( ste ),
	// resb originally cmpcs_n | dcyc_n internally in shifter,
	// but we have the luxury of having a reset pin
	.resb       ( ~peripheral_reset ),

	// CPU/RAM interface
	.CS         ( ~cmpcs_n ),
	.A          ( mbus_a[6:1] ),
	.DIN        ( mbus_dout ),
	.DOUT       ( shifter_dout ),
	.LATCH      ( latch ),
	.RDAT_N     ( rdat_n ),   // latched MDIN -> DOUT
	.WDAT_N     ( wdat_n ),   // DIN  -> MDOUT
	.RW         ( rw ),
	.MDIN       ( ram_data_out ),
	.MDOUT      ( ram_data_in  ),

	// VIDEO
	.MONO_OUT   ( mono ),
	.LOAD_N     ( dcyc_n ),
	.DE         ( de ),
	.BLANK_N    ( blank_n ),
	.R          ( r ),
	.G          ( g ),
	.B          ( b ),

	// DMA SOUND
	.SLOAD_N    ( sload_n ),
	.SREQ       ( sreq ),
	.audio_left ( dma_snd_l ),
	.audio_right( dma_snd_r )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ CPU ------------------------------------- */
/* ------------------------------------------------------------------------------ */

/* --- experimental 16Mhz turbo mode --- */
   
wire cpu_16mhz_enable = 1'b0;  
   
wire		clk16_en = ~clk16;
wire		phi1 = cpu_16mhz_enable? clk16_en:mhz8_en1;   
wire		phi2 = cpu_16mhz_enable?~clk16_en:mhz8_en2;  

// In 16mhz the dtack for ram and rom needs to be delayed, so the cycle
// would not get too short as our ram and rom aren't very fast.
// Especially the serial SPI rom already runs close to the limits.
reg		  as_n_D;
reg	[3:0] as_n_cnt;   

// run a counter from the begin of as_n   
always @(posedge clk_32) begin
   as_n_D <= cpu_as_n;
   if(!cpu_as_n) begin
	  if(as_n_D)
		as_n_cnt <= 4'd0;
	  else begin
		 // make sure counter does not run while RAM is accessed and ram is in refresh
		 // or being used for video
		 if(as_n_cnt != 4'd15 && !(cpu_a[23:22] == 2'b00 && (ram_ref || !dcyc_n)))
		   as_n_cnt <= as_n_cnt + 4'd1;
	  end
   end else
	 as_n_cnt <= 4'd0;
end

wire rom = !cpu_as_n && (cpu_a[23:18] == 6'b111111);
wire ram = !cpu_as_n && (cpu_a[23:22] == 2'b00);   
	 
wire mcu_dtack_n_adj = 
	 !cpu_16mhz_enable ? mcu_dtack_n:      // normal dtack in non-turbo mode
//	 (rom && as_n_cnt<6)?1'b1:  // suppress dtack at begin of rom cycle
//	 (ram && as_n_cnt<6)?1'b1:  // suppress dtack at begin of ram cycle
	 (as_n_cnt<7)?1'b1:  // suppress dtack at begin of cycle
	 mcu_dtack_n;

fx68k fx68k (
	.clk        ( clk_32     ),
	.extReset   ( reset      ),
	.pwrUp      ( !porb      ),
	.enPhi1     ( phi1       ),
	.enPhi2     ( phi2       ),

	.eRWn       ( cpu_rw    ),
	.ASn        ( cpu_as_n  ),
	.LDSn       ( cpu_lds_n ),
	.UDSn       ( cpu_uds_n ),
	.E          ( cpu_E     ),
	.VMAn       ( vma_n     ),
	.FC0        ( cpu_fc0   ),
	.FC1        ( cpu_fc1   ),
	.FC2        ( cpu_fc2   ),
	.BGn        ( blitter_bg_n  ),
	.oRESETn    ( cpu_reset_n_o ),
	.oHALTEDn   (),
	.DTACKn     ( dtack_n    ),
	.VPAn       ( vpa_n      ),
	.BERRn      ( berr_n     ),
`ifndef VERILATOR
	.HALTn      ( 1'b1       ),
`endif
	.BRn        ( blitter_br_n & mcu_br_n ),
	.BGACKn     ( blitter_bgack_n ),
	.IPL0n      ( ipl0_n     ),
	.IPL1n      ( ipl1_n     ),
	.IPL2n      ( ipl2_n     ),
	.iEdb       ( cpu_din    ),
	.oEdb       ( cpu_dout   ),
	.eab        ( cpu_a      )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ MFP ------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire acia_irq = kbd_acia_irq || midi_acia_irq;

// the STE delays the xsirq by 1/250000 second before feeding it into timer_a
// 74ls164
wire      xsint = ~sint;
reg [7:0] xsint_delay;
always @(posedge clk_32 or negedge xsint) begin
	if(!xsint) xsint_delay <= 8'h00;            // async reset
	else if (clk_2_en) xsint_delay <= {xsint_delay[6:0], xsint};
end

wire xsint_delayed = xsint_delay[7];

// mfp io7 is mono_detect which in ste is xor'd with the dma sound irq
wire mfp_io7 = mono_detect ^ (ste?xsint:1'b0);

wire acsi_irq, fdc_irq;

// inputs 1,2 and 6 are outputs from an MC1489 serial receiver
wire  [7:0] mfp_gpio_in = {mfp_io7, 1'b1, !(acsi_irq | fdc_irq), !acia_irq, blitter_irq_n, 2'b11, parallel_busy};
wire  [1:0] mfp_timer_in = {de, ste?xsint_delayed:parallel_busy};
wire  [7:0] mfp_data_out;
wire        mfp_dtack;

wire        mfp_int;
wire        mfp_iack = ~mfpiack_n;
assign      mfpint_n = ~mfp_int;

mfp mfp (
	// cpu register interface
	.clk      ( clk_32        ),
	.clk_en   ( mhz4_en       ),
	.reset    ( peripheral_reset ),
	.din      ( mbus_dout[7:0]),
	.sel      ( ~mfpcs_n      ),
	.addr     ( mbus_a[5:1]   ),
	.ds       ( lds_n         ),
	.rw       ( rw            ),
	.dout     ( mfp_data_out  ),
	.irq      ( mfp_int       ),
	.iack     ( mfp_iack      ),
	.dtack    ( mfp_dtack     ),

	// serial/rs232 interface io-controller<->mfp
	.serial_status_out         (serial_status),

	.serial_data_out_available (serial_tx_available),
	.serial_strobe_out         (serial_tx_strobe),
	.serial_data_out           (serial_tx_data),

	.serial_data_in_free       (serial_rx_available),
	.serial_strobe_in          (serial_rx_strobe),
	.serial_data_in            (serial_rx_data),

	// input signals
	.clk_ext  ( clk_mfp_en    ),  // 2.457MHz clock enable
	.t_i      ( mfp_timer_in  ),  // timer a/b inputs
	.i        ( mfp_gpio_in   )   // gpio-in
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- IKBD -------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire ikbd_tx, ikbd_rx;

ikbd #( .DIV(4) ) ikbd (
	.clk(clk_32),		    // clock is divided to 2MHz (/16 == 2^4) inside ikbd
	.res(peripheral_reset),
      
	.tx(ikbd_tx),
	.rx(ikbd_rx),
	   
    .matrix_out(keyboard_matrix_out),
    .matrix_in(keyboard_matrix_in),

    .caps_lock(),

	.joystick0({joy0[5:4], joy0[0], joy0[1], joy0[2], joy0[3]}),
	.joystick1({joy1[  4], joy1[0], joy1[1], joy1[2], joy1[3]})
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- keyboard ACIA -------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] kbd_acia_data_out;
wire       kbd_acia_irq;

acia #( .INPUT_FILTER(0) ) kbd_acia (
	// cpu interface
	.clk      ( clk_32             ),
	.E        ( cpu_E              ),
	.reset    ( reset              ),
	.din      ( mbus_dout[15:8]    ),
	.sel      ( n6850 & ~mbus_a[2] ),
	.rs       ( mbus_a[1]          ),
	.rw       ( rw                 ),
	.dout     ( kbd_acia_data_out  ),
	.irq      ( kbd_acia_irq       ),

    .rxtxclk_sel( 1'b0             ),
    .dout_strobe(                  ),

	.rx       ( ikbd_tx            ),
	.tx       ( ikbd_rx            )
);

/* ------------------------------------------------------------------------------ */
/* --------------------------------- MIDI ACIA ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] midi_acia_data_out;
wire       midi_acia_irq;

acia midi_acia (
	// cpu interface
	.clk      ( clk_32             ),
	.E        ( cpu_E              ),
	.reset    ( reset              ),
	.din      ( mbus_dout[15:8]    ),
	.sel      ( n6850 & mbus_a[2]  ),
	.rs       ( mbus_a[1]          ),
	.rw       ( rw                 ),
	.dout     ( midi_acia_data_out ),
	.irq      ( midi_acia_irq      ),

    .rxtxclk_sel( 1'b0             ),

	.rx       ( midi_rx            ),
	.tx       ( midi_tx            ),

	// redirected midi interface
	.dout_strobe ( )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ PSG ------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire       snd_data_oe_l;
wire [7:0] ym_a_out, ym_b_out, ym_c_out;

wire [9:0] ym_audio_out_l;
wire [9:0] ym_audio_out_r;

reg clk_2_en;
always @(posedge clk_32) begin
	reg [3:0] cnt;
	clk_2_en <= (cnt == 0);
	cnt <= cnt + 1'd1;
end

wire [7:0] port_a_in = { port_a_out[7:6], parallel_strobe_in, port_a_out[4:0] };
wire [7:0] port_a_out;
wire	   port_a_oe;
   
wire [7:0] port_b_in = parallel_data_in;
wire [7:0] port_b_out;
wire	   port_b_oe;   
   
wire       floppy_side = port_a_out[0];
wire [1:0] floppy_sel = port_a_out[2:1];

assign  parallel_strobe_oe = port_a_oe;   
assign  parallel_strobe_out = port_a_out[5];
assign  parallel_data_oe = port_b_oe;
assign  parallel_data_out = port_b_out;

assign ym_audio_out_r = ym_audio_out_l;   
assign snd_data_oe_l = !(sndir == 1'b0 && sndcs == 1'b1); 
   
jt49_bus jt49_bus (
 .rst_n(~peripheral_reset),
 .clk(clk_32),     // signal on positive edge
 .clk_en(clk_2_en)   /* synthesis direct_enable = 1 */,
 // bus control pins of original chip
 .bdir(sndir),
 .bc1(sndcs),
 .din(mbus_dout[15:8]),
 
 .sel(1'b1), // if sel is low, the clock is divided by 2
 .dout(snd_data_out),
 .sound(ym_audio_out_l),  // combined channel output
 .A(),      // linearised channel output
 .B(),
 .C(),
 .sample(),
 
 .IOA_in(port_a_in),
 .IOA_out(port_a_out),
 .IOA_oe(port_a_oe),
 
 .IOB_in(port_b_in),
 .IOB_out(port_b_out),
 .IOB_oe(port_b_oe)
 );
  
// audio output processing

// YM and STE audio channels are expanded to 14 bits and added resulting in 15 bits
// for the sigmadelta dac taken from the minimig

// This should later be handled by the lmc1992

wire [9:0] ym_audio_out_l_signed = ym_audio_out_l - 10'h200;
wire [9:0] ym_audio_out_r_signed = ym_audio_out_r - 10'h200;
wire [7:0] ste_audio_out_l_signed = dma_snd_l - 8'h80;
wire [7:0] ste_audio_out_r_signed = dma_snd_r - 8'h80;

assign audio_mix_l =
        { ym_audio_out_l_signed[9], ym_audio_out_l_signed, ym_audio_out_l_signed[9:6]} +
        { ste_audio_out_l_signed[7], ste_audio_out_l_signed, ste_audio_out_l_signed[7:2] };
assign audio_mix_r =
        { ym_audio_out_r_signed[9], ym_audio_out_r_signed, ym_audio_out_r_signed[9:6]} +
        { ste_audio_out_r_signed[7], ste_audio_out_r_signed, ste_audio_out_r_signed[7:2] };

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- Blitter ----------------------------------- */
/* ------------------------------------------------------------------------------ */
wire        blitter_irq_n;

wire        blitter_as_n;
wire        blitter_ds_n;
wire        blitter_rw_n;
wire        blitter_fc0 = 1'b1, blitter_fc1 = 1'b0, blitter_fc2 = 1'b1;
wire        blitter_dtack_n;
wire [23:1] blitter_addr;
wire        blitter_has_bus;

`ifndef EFINIX
// EFINIX doesn't like this ...
blt_clks Clks;

assign Clks.clk = clk_32;
assign Clks.aRESETn = !peripheral_reset;
assign Clks.sReset = !porb | peripheral_reset;
assign Clks.pwrUp = !porb;

assign Clks.enPhi1 = cpu_16mhz_enable? clk16_en:mhz8_en1;
assign Clks.enPhi2 = cpu_16mhz_enable?~clk16_en:mhz8_en2;
assign Clks.anyPhi = Clks.enPhi2 | Clks.enPhi1;

assign { Clks.extReset, Clks.phi1, Clks.phi2} = 3'b000;
`endif

wire mblit_selected;
wire mblit_oBGACKn;

stBlitter stBlitter(
`ifndef EFINIX
	.Clks     ( Clks ),
`else
    .clk(clk_32),
    .aRESETn(!peripheral_reset),
    .sReset(!porb | peripheral_reset),
    .pwrUp(!porb),

    .enPhi1(cpu_16mhz_enable? clk16_en:mhz8_en1),
    .enPhi2(cpu_16mhz_enable?~clk16_en:mhz8_en2),
`endif
	.ASn      ( as_n | ~blitter_en ),
	.RWn      ( cpu_rw ),
	.LDSn     ( lds_n ),
	.UDSn     ( uds_n ),
	.FC0      ( fc0 ),
	.FC1      ( fc1 ),
	.FC2      ( fc2 ),
	.BERRn    ( berr_n ),
	.iDTACKn  ( dtack_n ),
	.ctrlOe   ( blitter_has_bus ),
	.dataOe   ( blitter_sel ),
	.oASn     ( blitter_as_n ),
	.oDSn     ( blitter_ds_n ),
	.oRWn     ( blitter_rw_n ),
	.oDTACKn  ( blitter_dtack_n ),
	.selected ( mblit_selected ),
	.iBRn     ( mcu_br_n ),
	.BGIn     ( blitter_bg_n ),
	.iBGACKn  ( mcu_bgack_n ),
	.oBRn     ( blitter_br_n ),
	.oBGACKn  ( mblit_oBGACKn ),
	.INTn     ( blitter_irq_n ),
	.BGOn     ( mcu_bg_n ),
	.dmaInput ( mbus_dout ),
	.iABUS    ( mbus_a ),
	.oABUS    ( blitter_addr ),
	.iDBUS    ( cpu_dout ),
	.oDBUS    ( blitter_data_out )
);

assign blitter_bgack_n = mblit_oBGACKn & mcu_bgack_n;		// This really happens inside Blitter
assign { blitter_fc2, blitter_fc1, blitter_fc0} = 3'b101;
   
/* ------------------------------------------------------------------------------ */
/* ---------------------------- STe controller ports ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire [15:0] ste_joy_in;
wire  [3:0] ste_buttons;
reg   [7:0] ste_joy_out;

wire  [7:0] ste_joy_out_pins = joywe_n ? 8'hff : ste_joy_out;

always @(posedge clk_32) begin
	if (joywl) ste_joy_out <= mbus_dout[7:0];
end

ste_joypad ste_joypad0 (
	.joy      ( 16'd0 ),
	.din      ( ste_joy_out_pins[3:0] ),
	.dout     ( { ste_joy_in[11:8], ste_joy_in[3:0] } ),
	.buttons  ( ste_buttons[1:0] )
);

ste_joypad ste_joypad1 (
	.joy      ( 16'd0 ),
	.din      ( ste_joy_out_pins[7:4] ),
	.dout     ( { ste_joy_in[15:12], ste_joy_in[7:4] } ),
	.buttons  ( ste_buttons[3:2] )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- Real-time clock ------------------------------ */
/* ------------------------------------------------------------------------------ */

// a dummy time to start with ...
wire [51:0] rtc = { 4'h6, 8'h23,8'h09,8'h03, 8'h13,8'h33,8'h00 };
   
reg [3:0] rtc_data_out;
reg       rtc_bank;
reg [3:0] rtc_bank1[16];

// RP5C15
always @(*) begin
	casez ({rtc_bank, mbus_a[4:1]})
		5'b0_0000: rtc_data_out = rtc[3:0]; // sec
		5'b0_0001: rtc_data_out = rtc[7:4];
		5'b0_0010: rtc_data_out = rtc[11:8]; // min
		5'b0_0011: rtc_data_out = rtc[15:12];
		5'b0_0100: rtc_data_out = rtc[19:16]; // hour
		5'b0_0101: rtc_data_out = rtc[23:20];
		5'b0_0110: rtc_data_out = rtc[51:48]; // day of week
		5'b0_0111: rtc_data_out = rtc[27:24]; // day
		5'b0_1000: rtc_data_out = rtc[31:28];
		5'b0_1001: rtc_data_out = rtc[35:32]; // month
		5'b0_1010: rtc_data_out = rtc[39:36];
		5'b0_1011: rtc_data_out = rtc[43:40]; // year
		5'b0_1100: rtc_data_out = rtc[47:44] + 4'd2; // GEMDOS fix: it assumes year 0 as 1980
		5'b?_1101: rtc_data_out = {1'b1, 2'b00, rtc_bank };
		5'b?_1110: rtc_data_out = 4'h0;
		5'b?_1111: rtc_data_out = 4'hc;
		5'b1_????: rtc_data_out = rtc_bank1[mbus_a[4:1]];
		default: rtc_data_out = 4'hf;
	endcase
	// make the RTC invisible if no valid RTC data arrives from the IO Controller
	if (rtc == 0) rtc_data_out = 4'hf;
end

always @(posedge clk_32) begin
	if (peripheral_reset) begin
		rtc_bank <= 0;
	end else begin
		if (!(rtccs_n | rtcwr_n)) begin
			if (mbus_a[4:1] == 4'hd)
				rtc_bank <= cpu_dout[0];
			else
				rtc_bank1[mbus_a[4:1]] <= cpu_dout[3:0];
		end
	end
end

/* ------------------------------------------------------------------------------ */
/* ------------------------------------- DMA ------------------------------------ */
/* ------------------------------------------------------------------------------ */

assign     leds[1:0] = floppy_sel ^ 2'b11;   
wire       fdc_drq;
wire [1:0] fdc_addr;
wire       fdc_sel;
wire       fdc_rw;
wire [7:0] fdc_din;
wire [7:0] fdc_dout;

wire dma_write, dma_read;

dma dma (
	// system interface
	.clk          ( clk_32        ),
	.clk_en       ( mhz8_en1      ),
	.reset        ( reset         ),

	// cpu interface
	.cpu_din      ( mbus_dout     ),
	.cpu_sel      ( ~fcs_n        ),
	.cpu_a1       ( mbus_a[1]     ),
	.cpu_rw       ( rw            ),
	.cpu_dout     ( dma_data_out  ),

	// SD card interface for ACSI
	.img_mounted  ( sd_img_mounted[3:2]         ), // signaling that new ACSI image has been mounted
	.img_size     ( sd_img_size                 ), // size of image mounted
	.acsi_rd_req  ( acsi_rd_req                 ),
	.acsi_wr_req  ( acsi_wr_req                 ),
	.acsi_lba     ( acsi_sd_lba                 ),
 	.sd_done      ( acsi_sd_done                ),
 	.sd_busy      ( acsi_sd_busy                ),
	.sd_rd_byte_strobe ( acsi_sd_rd_byte_strobe ),
	.sd_rd_byte   ( acsi_sd_rd_byte             ),
	.sd_wr_byte   ( acsi_sd_wr_byte             ),
	.sd_byte_addr ( acsi_sd_byte_addr           ),

	// additional signals for ACSI interface
	.acsi_irq     ( acsi_irq    ),

	// FDC interface
	.fdc_drq      ( fdc_drq  ),
	.fdc_addr     ( fdc_addr ),
	.fdc_sel      ( fdc_sel  ),
	.fdc_rw       ( fdc_rw   ),
	.fdc_din      ( fdc_din  ),
	.fdc_dout     ( fdc_dout ),

	// ram interface
	.rdy_i        ( rdy_i        ),
	.rdy_o        ( rdy_o        ),
	.ram_din      ( shifter_dout ),

    .hdd_leds     ( leds[3:2] )
);

// Some broken software selects both drives at the same time. On real hardware this
// only works if no second drive is present. In our setup the second drive is present
// but we can simply map all such broken accesses to drive A only
wire [1:0] floppy_sel_exclusive = (floppy_sel == 2'b00)?2'b10:floppy_sel;

// TODO: check why floppy is not detected at all if no image is mounted
// -> waits for spin up, but no index pulses
// Fix: Floppy should generate index pulses even without disk inserted
   
fdc1772 fdc1772 (
	.clkcpu         ( clk_32           ), // system cpu clock.
	.clk8m_en       ( mhz8_en1         ),

	// external set signals
	.floppy_drive   ( floppy_sel_exclusive ),
	.floppy_side    ( floppy_side      ),
	.floppy_reset   ( ~peripheral_reset),
    .floppy_step    (                  ),
    .floppy_motor   ( 1'b0             ),  // unused in ST

	// interrupts
	.irq            ( fdc_irq          ),
	.drq            ( fdc_drq          ),

	.cpu_addr       ( fdc_addr         ),
	.cpu_sel        ( fdc_sel          ),
	.cpu_rw         ( fdc_rw           ),
	.cpu_din        ( fdc_din          ),
	.cpu_dout       ( fdc_dout         ),

	// place any signals that need to be passed up to the top after here.
	.img_ds         ( 1'b0                ), // "double sided" image. Unused in ST
	.img_type       ( 3'd1                ), // Atari ST floppy type
	.img_wp         ( floppy_protected    ), // write protect
	.img_mounted    ( sd_img_mounted[1:0] ), // signaling that new image has been mounted
	.img_size       ( sd_img_size[31:0]   ), // size of image in bytes, 737280 for 80 tracks, 9 spt double sided

	.sd_lba         ( sd_lba              ), // sector requested by fdc to be read/written
	.sd_rd          ( sd_rd               ), // read request for two floppy drives
	.sd_wr          ( sd_wr               ), // write request for two floppy drives
	.sd_ack         ( sd_ack              ), // ackknowledge data transfer
	.sd_buff_addr   ( sd_buff_addr        ), // number of byte being transferred
	.sd_dout        ( sd_dout             ), // data read by fdc
	.sd_din         ( sd_din              ), // data written by fdc
	.sd_dout_strobe ( sd_dout_strobe      )  // byte ready to be read by fdc
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- Cubase dongle  ------------------------------- */
/* ------------------------------------------------------------------------------ */
assign cart_data_out = { cubase_en ? cubase_dout : 8'hff, 8'hff};  

wire        cubase3_d8;
wire  [7:0] cubase2_dout;
wire  [7:0] cubase_dout = cubase_sel ? cubase2_dout : {7'h7f, cubase3_d8};
reg         cubase_sel; // Cubase3/2 dongle
reg         cubase_lock;

always @(posedge clk_32) begin
	if (peripheral_reset) begin
		cubase_sel <= 0;
		cubase_lock <= 0;
	end
	else if (cubase_en & !cart_n & !cubase_lock) begin
		cubase_sel <= |mbus_a[7:1];
		cubase_lock <= 1;
	end
end

cubase2_dongle cubase2_dongle (
	.clk        ( clk_32           ),
	.reset      ( peripheral_reset ),
	.uds_n      ( uds_n            ),
	.A          ( mbus_a[8:1]      ),
	.D          ( cubase2_dout     )
);

cubase3_dongle cubase3_dongle (
	.clk        ( clk_32           ),
	.reset      ( peripheral_reset ),
	.rom3_n     ( cart_n           ),
	.a8         ( mbus_a[8]        ),
	.d8         ( cubase3_d8       )
);

endmodule

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:

