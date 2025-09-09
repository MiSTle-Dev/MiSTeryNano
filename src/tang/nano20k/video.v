// video.v

module video (
	      input	   clk_pixel,
	      input	   por,

	      input	   vs_in_n,
	      input	   hs_in_n,
	      input	   de_in,
	      input [3:0]  r_in,
	      input [3:0]  g_in,
	      input [3:0]  b_in,

              input [15:0] audio_l,
              input [15:0] audio_r,

              // (spi) interface from MCU
              input	   mcu_start,
              input	   mcu_osd_strobe,
              input [7:0]  mcu_data,

              output	   vreset,
              output [1:0] vmode,

              // values that can be configure by the user via osd          
              input [1:0]  system_scanlines,
              input	   system_wide_screen,
              input	   system_scandoubler,

              // digital video out for lcd
              output	   lcd_clk,
              output	   lcd_hs_n,
              output	   lcd_vs_n,
              output	   lcd_de,
              output [5:0] lcd_r,
              output [5:0] lcd_g,
              output [5:0] lcd_b
);
   
/* -------------------- HDMI video and audio -------------------- */

video_analyzer video_analyzer (
   .clk(clk_pixel),
   .vs(vs_in_n),
   .hs(hs_in_n),
   .de(de_in),

   .wide(system_wide_screen),
   .mode(vmode),
   .vreset(vreset)  // reset signal
);  

wire sd_hs_n, sd_vs_n; 
wire [5:0] sd_r;
wire [5:0] sd_g;
wire [5:0] sd_b;

scandoubler #(10) scandoubler (
        // system interface
        .clk_sys(clk_pixel),
        .bypass(vmode == 2'd2 || !system_scandoubler), // always bypass in ST high/mono
        .ce_divider(1'b1),
        .pixel_ena(),

        // scanlines (00-none 01-25% 10-50% 11-75%)
        .scanlines(system_scanlines),

        // shifter video interface
        .hs_in(hs_in_n),
        .vs_in(vs_in_n),
        .r_in( r_in ),
        .g_in( g_in ),
        .b_in( b_in ),

        // output interface
        .hs_out(sd_hs_n),
        .vs_out(sd_vs_n),
        .r_out(sd_r),
        .g_out(sd_g),
        .b_out(sd_b)
);

osd_u8g2 osd_u8g2 (
        .clk(clk_pixel),
        .reset(por),

        .data_in_strobe(mcu_osd_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data),

        .hs(sd_hs_n),
        .vs(sd_vs_n),
		     
        .r_in(sd_r),
        .g_in(sd_g),
        .b_in(sd_b),
		     
        .r_out(lcd_r),
        .g_out(lcd_g),
        .b_out(lcd_b)
);   

assign lcd_clk = clk_pixel;
assign lcd_hs_n = sd_hs_n;
assign lcd_vs_n = sd_vs_n;

reg [9:0] hcnt;   // max 1023
reg [9:0] vcnt;   // max 626

// generate lcd de signal
// this needs adjustment for each ST video mode
localparam XNTSC = 10'd920;
localparam YNTSC = 10'd990;
localparam XPAL  = 10'd920;
localparam YPAL  = 10'd930;
localparam XHIGH = 10'd955;
localparam YHIGH = 10'd0;

assign lcd_de = (hcnt < 10'd800) && (vcnt < 10'd480);

// after scandoubler (with dim lines), ste video is 3*6 bits
// lcd r and b are only 5 bits, so there may be some color
// offset
   
always @(posedge clk_pixel) begin
   reg 	     last_vs_n, last_hs_n;

   last_hs_n <= lcd_hs_n;   

   // rising edge/end of hsync
   if(lcd_hs_n && !last_hs_n) begin
      hcnt <= 
        (vmode == 2'd0)?XNTSC:
        (vmode == 2'd1)?XPAL:
                        XHIGH;
      
      last_vs_n <= lcd_vs_n;   
      if(lcd_vs_n && !last_vs_n) begin
        vcnt <=
        (vmode == 2'd0)?YNTSC:
        (vmode == 2'd1)?YPAL:
                        YHIGH;
      end else
	vcnt <= vcnt + 10'd1;    
   end else
      hcnt <= hcnt + 10'd1;    
end

endmodule
