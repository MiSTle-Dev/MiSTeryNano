// atarist_tb.v - Atari ST MiSTeryNano verilator testbench

module atarist_tb (
	// System clocks / reset / settings
        input wire	   clk_32,
        input wire	   porb,
        input wire	   resb,
	
        // Video output
        input wire	   mono_detect, // low for monochrome
        output wire [5:0]  r,
        output wire [5:0]  g,
        output wire [5:0]  b,
        output wire	   hsync_n,
        output wire	   vsync_n,

	// floppy disk/sd card interface
	output		   sdclk,
	output		   sdcmd,
	input		   sdcmd_in,
	output [3:0]	   sddat,
	input [3:0]	   sddat_in,

	input		   mcu_data_strobe,
	input		   mcu_data_start,
	input [7:0]	   mcu_data_in,
	output [7:0]	   mcu_data_out,
	output		   mcu_irq,
	input		   mcu_iack,

	// DRAM interface
        output wire	   ram_ras_n,
        output wire	   ram_cash_n,
        output wire	   ram_casl_n,
        output wire	   ram_we_n,
        output wire	   ram_ref,
        output wire [23:1] ram_addr,
        output wire [15:0] ram_data_in,
        input wire [15:0]  ram_data_out,

        // TOS ROM interface
        output wire	   rom_n, 
        output wire [23:1] rom_addr,
        input wire [15:0]  rom_data_out,

        // export all LEDs
        output wire [3:0]  leds
);

wire [63:0]		   sd_img_size;
wire [7:0]		   sd_img_mounted;   
  
wire [1:0]	fdc_rd_req;
wire [1:0]	fdc_wr_req;
wire [1:0]	acsic_rd_req;
wire [1:0]	acsi_wr_req;

wire [31:0]	fdc_lba;
wire [31:0]	acsi_lba;  
wire [7:0]	acsi_sd_wr_byte;
wire [7:0]	fdc_sd_wr_data;   

wire		sd_busy, sd_done;
wire		sd_rd_byte_strobe;
wire [8:0]	sd_byte_index;   
wire [7:0]	sd_rd_data;
   
// differentiate between floppy and acsi requests
reg [7:0] sdc_rd = 8'h00;
reg [7:0] sdc_wr = 8'h00;   
reg      is_acsi = 0;

always @(posedge clk_32) begin
   // toggle between floppy and acsi data paths to the sd card
   if(|{fdc_rd_req,fdc_wr_req}) begin
      is_acsi <= 1'b0;
      if(is_acsi) $display("ACSI disabled");      
   end
      
   if(|{acsi_rd_req,acsi_wr_req}) begin
      is_acsi <= 1'b1;
      if(!is_acsi) $display("ACSI enabled");      
   end

   sdc_rd <= { 4'h0, acsi_rd_req, fdc_rd_req };
   sdc_wr <= { 4'h0, acsi_wr_req, fdc_wr_req };   
end

sd_card #(
    .CLK_DIV(3'd0),                   // for 32 Mhz clock -> sd card clock = 16Mhz
    .SIMULATE(1'b1)
) sd_card (
    .rstn(porb),                      // rstn active-low, 1:working, 0:reset
    .clk(clk_32),                     // clock
  
    // SD card signals
    .sdclk(sdclk),
    .sdcmd(sdcmd),
    .sdcmd_in(sdcmd_in),
    .sddat(sddat),
    .sddat_in(sddat_in),
    
    // mcu interface
    .data_strobe(mcu_data_strobe),
    .data_start(mcu_data_start),
    .data_in(mcu_data_in),
    .data_out(mcu_data_out),

    // output file/image information. Image size is e.g. used by fdc to 
    // translate between sector/track/side and lba sector
    .image_size(sd_img_size),           // length of image file
    .image_mounted(sd_img_mounted),

    // interrupt to signal communication request
    .irq(mcu_irq),
    .iack(mcu_iack),

    // user read sector command interface (sync with clk32)
    .rstart( sdc_rd ), 
    .wstart( sdc_wr ), 
    .rsector( is_acsi?acsi_lba:fdc_lba),
    .inbyte(is_acsi?acsi_sd_wr_byte:fdc_sd_wr_data),

    .rbusy(sd_busy),
    .rdone(sd_done),
		   
    // sector data output interface (sync with clk32)
    .outen(sd_rd_byte_strobe), // when outen=1, a byte of sector content is read out from outbyte
    .outaddr(sd_byte_index),   // outaddr from 0 to 511, because the sector size is 512
    .outbyte(sd_rd_data)       // a byte of sector content
);

wire st_vs_n, st_hs_n, st_de;  
wire [3:0] st_r;
wire [3:0] st_g;
wire [3:0] st_b;
   
atarist atarist (
	// System clocks / reset / settings
        .clk_32(clk_32),
	.porb(porb),
        .resb(resb),
	
        // Video output
        .mono_detect(mono_detect), // low for monochrome
        .r(st_r),
        .g(st_g),
        .b(st_b),
        .hsync_n(st_hs_n),
        .vsync_n(st_vs_n),
        .de(st_de),
        .blank_n(),
	
	// keyboard(), mouse and joystick(s)
        .keyboard_matrix_out(),
        .keyboard_matrix_in(8'hff),
        .joy0(6'b000000),
        .joy1(5'b00000),
	
        // Sound 
        .audio_mix_l(),
        .audio_mix_r(),
	
	// floppy disk/sd card interface
        .sd_lba(fdc_lba),
        .sd_rd(fdc_rd_req),
        .sd_wr(fdc_wr_req),
        .sd_ack(sd_busy),
        .sd_buff_addr(sd_byte_index),
        .sd_dout(sd_rd_data),
        .sd_din(fdc_din),
        .sd_dout_strobe(sd_rd_byte_strobe),
	
        // generic sd card services
        .sd_img_mounted(sd_img_mounted),
        .sd_img_size(sd_img_size),
	
	// ACSI disk/sd card interface
	.acsi_rd_req(acsi_rd_req),
	.acsi_wr_req(acsi_wr_req),
	.acsi_sd_lba(acsi_lba),
 	.acsi_sd_done(sd_done),
 	.acsi_sd_busy(sd_busy),
	.acsi_sd_rd_byte_strobe(sd_rd_byte_strobe),
	.acsi_sd_rd_byte(sd_rd_data),
	.acsi_sd_wr_byte(acsi_sd_wr_byte),
	.acsi_sd_byte_addr(sd_byte_index),
        
	// serial/rs232 to MCU
        .serial_tx_available(),
        .serial_tx_strobe(1'b0),
        .serial_tx_data(),
        .serial_rx_strobe(1'b0),
        .serial_rx_data(8'd0),
	
        // MIDI UART
        .midi_rx(1'b0),
        .midi_tx(),
	
        // printer signals
        .parallel_strobe_oe(),
        .parallel_strobe_in(1'b0), 
        .parallel_strobe_out(), 
        .parallel_data_oe(),
        .parallel_data_in(8'd0),
        .parallel_data_out(),
        .parallel_busy(1'b0), 
	
	// enable STE and extra 8MB ram
        .ste(1'b0),
        .enable_extra_ram(1'b0),
        .blitter_en(1'b1),
	.floppy_protected(1'b1), // floppy A/B write protect
	.cubase_en(1'b0),

	// DRAM interface
	.ram_ras_n(ram_ras_n),
	.ram_cash_n(ram_cash_n),
	.ram_casl_n(ram_casl_n),
	.ram_we_n(ram_we_n),
	.ram_ref(ram_ref),
	.ram_addr(ram_addr),
	.ram_data_in(ram_data_in),
	.ram_data_out(ram_data_out),
	
        // TOS ROM interface
        .rom_n(rom_n), 
        .rom_addr(rom_addr),
        .rom_data_out(rom_data_out),
	
        // export all LEDs
        .leds(leds)
);

// rund video through the video analyzer and the scan doubler
wire [1:0] vmode;      
video_analyzer video_analyzer (
   .clk(clk_32),
   .vs(st_vs_n),
   .hs(st_hs_n),
   .de(st_de),

   .mode(vmode),
   .vreset()
);  

wire sd_hs_n, sd_vs_n; 
  
scandoubler #(10) scandoubler (
        // system interface
        .clk_sys(clk_32),
        .bypass(vmode == 2'd2),      // bypass in ST high/mono
        .ce_divider(1'b1),
        .pixel_ena(),

        // scanlines (00-none 01-25% 10-50% 11-75%)
        .scanlines(2'b00),

        // shifter video interface
        .hs_in(st_hs_n),
        .vs_in(st_vs_n),
        .r_in( st_r ),
        .g_in( st_g ),
        .b_in( st_b ),

        // output interface
        .hs_out(hsync_n),
        .vs_out(vsync_n),
        .r_out(r),
        .g_out(g),
        .b_out(b)
);

// integrate ACSI HDD
   
endmodule; // atarist_tb
