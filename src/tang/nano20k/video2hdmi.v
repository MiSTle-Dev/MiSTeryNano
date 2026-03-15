// video2hdmi.v

module video2hdmi (
          input clk_pixel_x5,   // 160 MHz HDMI clock
          input clk_pixel,      // at 800x576@50Hz the pixel clock is 32 MHz
	      
          // video control inputs
          input        vreset,   // top/left pixel reached
          input [1:0]  vmode,    // Atari ST video mode
          input [1:0]  screen,   // screen mode (std, overscan, wide)

          input [5:0]  r,
	  input [5:0]  g,
	  input [5:0]  b,

          // audio is encoded into the video
          input [15:0] audio[2],

	  // hdmi/tdms
	  output       tmds_clk_n,
	  output       tmds_clk_p,
	  output [2:0] tmds_d_n,
	  output [2:0] tmds_d_p  
);

parameter          PIXEL_CLOCK = 32_000_000;   

/* -------------------- HDMI video and audio -------------------- */

// generate 48khz audio clock
reg clk_audio;
reg [8:0] aclk_cnt;
always @(posedge clk_pixel) begin
    if(aclk_cnt < PIXEL_CLOCK / 48000 / 2 -1)
        aclk_cnt <= aclk_cnt + 9'd1;
    else begin
        aclk_cnt <= 9'd0;
        clk_audio <= ~clk_audio;
    end
end

wire [2:0] tmds;
wire tmds_clock;

hdmi #(
    .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
    .VENDOR_NAME( { "MiSTle", 16'd0} ),
    .PRODUCT_DESCRIPTION( {"Atari ST", 64'd0} )
) hdmi(
  .clk_pixel_x5(clk_pixel_x5),
  .clk_pixel(clk_pixel),
  .clk_audio(clk_audio),
  .audio_sample_word( { audio[0], audio[1] } ),
  .tmds(tmds),
  .tmds_clock(tmds_clock),

  // video input
  .stmode(vmode),    // current video mode PAL/NTSC/MONO
  .screen(screen),   // adopt to various screen modes (std, overscan, wide)
  .reset(vreset),    // signal to synchronize HDMI

  // Atari STE outputs 4 bits per color. Scandoubler outputs 6 bits (to be
  // able to implement dark scanlines) and HDMI expects 8 bits per color
  .rgb( { r, 2'b00, g, 2'b00, b, 2'b00 } )
);

// differential output
ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
);

endmodule
