// Implementation of HDMI Spec v1.4a
// By Sameer Puri https://github.com/sameer

// The original hdmi.sv generated its own timing completely independent.
// This version synchronizes to an external sync signal which is expected to
// have exactly half the horizontal refresh rate.

module hdmi 
#(
    // The IT content bit indicates that image samples are generated in an ad-hoc
    // manner (e.g. directly from values in a framebuffer, as by a PC video
    // card) and therefore aren't suitable for filtering or analog
    // reconstruction.  This is probably what you want if you treat pixels
    // as "squares".  If you generate a properly bandlimited signal or obtain
    // one from elsewhere (e.g. a camera), this can be turned off.
    //
    // This flag also tends to cause receivers to treat RGB values as full
    // range (0-255).
    parameter bit IT_CONTENT = 1'b1,

    // As specified in Section 7.3, the minimal audio requirements are met: 16-bit or more L-PCM audio at 32 kHz, 44.1 kHz, or 48 kHz.
    // See Table 7-4 or README.md for an enumeration of sampling frequencies supported by HDMI.
    // Note that sinks may not support rates above 48 kHz.
    parameter int AUDIO_RATE = 44100,

    // Defaults to 16-bit audio, the minmimum supported by HDMI sinks. Can be anywhere from 16-bit to 24-bit.
    parameter int AUDIO_BIT_WIDTH = 16,

    // Some HDMI sinks will show the source product description below to users (i.e. in a list of inputs instead of HDMI 1, HDMI 2, etc.).
    // If you care about this, change it below.
    parameter bit [8*8-1:0] VENDOR_NAME = {"Unknown", 8'd0}, // Must be 8 bytes null-padded 7-bit ASCII
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 96'd0}, // Must be 16 bytes null-padded 7-bit ASCII
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00 // See README.md or CTA-861-G for the list of valid codes
)
(
    input logic			      clk_pixel_x5,
    input logic			      clk_pixel,
    input logic			      clk_audio,
    // synchronous reset back to 0,0
    input logic			      reset,
    input logic [1:0]		      stmode, // atari st video mode, 0=60hz ntsc, 1=50hz pal, 2=mono
    input logic [1:0]		      shmode, // atari st shift mode, 0=low, 1=mid, 2=high
    input logic			      wide,   // try to adopt to wide (16:9) screens
    input logic			      scandoubler,
    input logic [23:0]		      rgb, 
    input logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],

    // These outputs go to your HDMI port
`ifdef EFINIX
    output logic [5:0] tmds,       // 6+2 pins/pmod used for hdmi
    output logic [1:0] tmds_clock
`else
   // These outputs go to your HDMI port
    output logic [2:0] tmds,
    output logic tmds_clock
`endif    
);

localparam int NUM_CHANNELS = 3;
logic hsync;
logic vsync;

logic [1:0] invert;

// stmode: 0=NTSC, 1=PAL, 2=MONO

// Atari ST in PAL outputs 840 pixels per line
// but (our) HDMI implementation expects the width to be a multiple of 16
// Also demos opening the screen can only address 832 pixels properly

// Frame height should be 625/525, but has to be 626/526 for Atari ST
// in PAL/NTSC mode

// The w.... timing variants are using some modified timing and may look
// on wide screens. Since the displayed area of these is wider than the
// actual data to be displayed, the start value indicated the number of
// (black) pixels before the active area starts

// Atari ST mode table:
//                          frame   screen s_start   s_len
// NTSC    848x484@60Hz  aspect 1.75    
wire [47:0] htiming0  = { 12'd1016, 12'd848, 12'd16, 12'd62 };  
wire [47:0] whtiming0 = { 12'd1016, 12'd928, 12'd16, 12'd32 };  
wire [39:0] vtiming0  = {  10'd526, 10'd484,  10'd9,  10'd6 };
wire [7:0] cea0 = 8'd2; // CEA is HDMI mode in group 1
   
// PAL     832x576@50hz  aspect 1.44   948x576@50hz
wire [47:0] htiming1  = { 12'd1024, 12'd832, 12'd24, 12'd72 };  
wire [47:0] whtiming1 = { 12'd1024, 12'd952, 12'd16, 12'd32 };
wire [39:0] vtiming1  = {  10'd626, 10'd576,  10'd5,  10'd5 };
wire [7:0] cea1 = 8'd17;

// detect usage of 242p/288p timing
wire	    lowrez = !scandoubler && shmode == 0;
wire	    midrez = !scandoubler && shmode == 1;   
   
// MONO    640x400@71hz  aspect 1.6    
wire [47:0] htiming2  = { 12'd896, 12'd640, 12'd24, 12'd72 };
wire [47:0] whtiming2 = { 12'd896, 12'd720, 12'd24, 12'd72 };
wire [39:0] vtiming2  = { 10'd501, 10'd400,  10'd5,  10'd5 };  
wire [7:0] cea2 = 8'd2;
   
wire [95:0]  timing0 = {  htiming0, vtiming0, cea0 };
wire [95:0] wtiming0 = { whtiming0, vtiming0, cea0 };
wire [95:0]  timing1 = {  htiming1, vtiming1, cea1 };
wire [95:0] wtiming1 = { whtiming1, vtiming1, cea1 };
wire [95:0]  timing2 = {  htiming2, vtiming2, cea2 };
wire [95:0] wtiming2 = { whtiming2, vtiming2, cea2 };

// select timing as indicated by control signals coming for Atari ST core
wire [95:0] timing = 
         !wide?( (stmode == 2'd0)?timing0:
                 (stmode == 2'd1)?timing1:
                  timing2):
               ( (stmode == 2'd0)?wtiming0:
                 (stmode == 2'd1)?wtiming1:
                  wtiming2);

// demux timing parameters, divide all horizontal /2 for lowrez with scandouber disabled
wire [11:0] frame_width       = lowrez?{1'b0, timing[95:85]}:timing[95:84];
wire [11:0] screen_width      = lowrez?{1'b0, timing[83:73]}:timing[83:72];
wire [11:0] hsync_pulse_start = lowrez?{1'b0, timing[71:61]}:timing[71:60];
wire [11:0] hsync_pulse_size  = lowrez?{1'b0, timing[59:49]}:timing[59:48];

// and all vertical /2 for low and midrez with scandouber disabled
wire [9:0] frame_height       = (lowrez || midrez)?{1'b0, timing[47:39]}:timing[47:38];
wire [9:0] screen_height      = (lowrez || midrez)?{1'b0, timing[37:29]}:timing[37:28];
wire [9:0] vsync_pulse_start  = (lowrez || midrez)?{1'b0, timing[27:19]}:timing[27:18];
wire [9:0] vsync_pulse_size   = (lowrez || midrez)?{1'b0, timing[17: 9]}:timing[17: 8];

wire [7:0] cea                = timing[7:0]; 
   
assign invert = 2'b11;

reg [11:0] cx;
reg [9:0] cy;

always_comb begin
    hsync <= invert[0] ^ (cx >= screen_width + hsync_pulse_start && cx < screen_width + hsync_pulse_start + hsync_pulse_size);
    // vsync pulses should begin and end at the start of hsync, so special
    // handling is required for the lines on which vsync starts and ends
    if (cy == screen_height + vsync_pulse_start - 1)
        vsync <= invert[1] ^ (cx >= screen_width + hsync_pulse_start);
    else if (cy == screen_height + vsync_pulse_start + vsync_pulse_size - 1)
        vsync <= invert[1] ^ (cx < screen_width + hsync_pulse_start);
    else
        vsync <= invert[1] ^ (cy >= screen_height + vsync_pulse_start && cy < screen_height + vsync_pulse_start + vsync_pulse_size);
end

localparam real VIDEO_RATE = 32E6;

// without scan doubler the pixel clock is half (in st mid) or even
// a quarter (in st low)   
reg [1:0]	clk_pixel_div;
always @(posedge clk_pixel)
  clk_pixel_div <= clk_pixel_div + 2'd1;
   
reg [1:0]	clk_pixel_x5_div;
always @(posedge clk_pixel_x5)
  clk_pixel_x5_div <= clk_pixel_x5_div + 2'd1;   

wire clk_pixel_int    = lowrez?clk_pixel_div[1]:   midrez?clk_pixel_div[0]:   clk_pixel;   
wire clk_pixel_x5_int = lowrez?clk_pixel_x5_div[1]:midrez?clk_pixel_x5_div[0]:clk_pixel_x5;   
   
// Wrap-around pixel position counters indicating the pixel to be generated by the user in THIS clock and sent out in the NEXT clock.
always_ff @(posedge clk_pixel_int)
begin
    if (reset)
    begin
        cx <= 11'd0;       
        cy <= 10'd0;    // start_y
    end
    else
    begin
        cx <= cx == frame_width-1'b1 ? 11'd0 : cx + 1'b1;
        cy <= cx == frame_width-1'b1 ? cy == frame_height-1'b1 ? 10'd0 : cy + 1'b1 : cy;
    end
end

// See Section 5.2
logic video_data_period = 0;
always_ff @(posedge clk_pixel_int)
begin
    if (reset)
        video_data_period <= 0;
    else
        video_data_period <= cx < screen_width && cy < screen_height;
end

logic [2:0] mode = 3'd1;
logic [23:0] video_data = 24'd0;
logic [5:0] control_data = 6'd0;
logic [11:0] data_island_data = 12'd0;

generate
    begin: true_hdmi_output
        logic video_guard = 1;
        logic video_preamble = 0;
        always_ff @(posedge clk_pixel_int)
        begin
            if (reset)
            begin
                video_guard <= 1;
                video_preamble <= 0;
            end
            else
            begin
                video_guard <= cx >= frame_width - 2 && cx < frame_width && (cy == frame_height - 1 || cy < screen_height - 1 /* no VG at end of last line */);
                video_preamble <= cx >= frame_width - 10 && cx < frame_width - 2 && (cy == frame_height - 1 || cy < screen_height - 1 /* no VP at end of last line */);
            end
        end

        // See Section 5.2.3.1
        int max_num_packets_alongside;
        logic [4:0] num_packets_alongside;
        always_comb
        begin
	    max_num_packets_alongside = (frame_width - screen_width  /* VD period */ - 2 /* V guard */ - 8 /* V preamble */ - 4 /* Min V control period */ - 2 /* DI trailing guard */ - 2 /* DI leading guard */ - 8 /* DI premable */ - 4 /* Min DI control period */) / 32;
            if (max_num_packets_alongside > 18)
                num_packets_alongside = 5'd18;
            else
                num_packets_alongside = 5'(max_num_packets_alongside);
        end

        logic data_island_period_instantaneous;
        assign data_island_period_instantaneous = num_packets_alongside > 0 && cx >= screen_width + 14 && cx < screen_width + 14 + num_packets_alongside * 32;
        logic packet_enable;
        assign packet_enable = data_island_period_instantaneous && 5'(cx + screen_width + 18) == 5'd0;

        logic data_island_guard = 0;
        logic data_island_preamble = 0;
        logic data_island_period = 0;
        always_ff @(posedge clk_pixel_int)
        begin
            if (reset)
            begin
                data_island_guard <= 0;
                data_island_preamble <= 0;
                data_island_period <= 0;
            end
            else
            begin
	        data_island_guard <= num_packets_alongside > 0 && (
                    (cx >= screen_width + 12 && cx < screen_width + 14) /* leading guard */ || 
                    (cx >= screen_width + 14 + num_packets_alongside * 32 && cx < screen_width + 14 + num_packets_alongside * 32 + 2) /* trailing guard */
                );
                data_island_preamble <= num_packets_alongside > 0 && cx >= screen_width + 4 && cx < screen_width + 12;
                data_island_period <= data_island_period_instantaneous;
            end
        end

        // See Section 5.2.3.4
        logic [23:0] header;
        logic [55:0] sub [3:0];
        logic video_field_end;
        assign video_field_end = cx == screen_width - 1'b1 && cy == screen_height - 1'b1;
        logic [4:0] packet_pixel_counter;
        packet_picker #(
            .VIDEO_RATE(VIDEO_RATE),
            .IT_CONTENT(IT_CONTENT),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME(VENDOR_NAME),
            .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
            .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
        ) packet_picker (.clk_pixel(clk_pixel_int), .clk_audio(clk_audio), .reset(reset), .cea(cea), .stmode(stmode), .video_field_end(video_field_end), .packet_enable(packet_enable), .packet_pixel_counter(packet_pixel_counter), .audio_sample_word(audio_sample_word), .header(header), .sub(sub));
        logic [8:0] packet_data;
        packet_assembler packet_assembler (.clk_pixel(clk_pixel_int), .reset(reset), .data_island_period(data_island_period), .header(header), .sub(sub), .packet_data(packet_data), .counter(packet_pixel_counter));


        always_ff @(posedge clk_pixel_int)
        begin
            if (reset)
            begin
                mode <= 3'd2;
                video_data <= 24'd0;
                control_data = 6'd0;
                data_island_data <= 12'd0;
            end
            else
            begin
                mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 : video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
                video_data <= rgb;
                control_data <= {{1'b0, data_island_preamble}, {1'b0, video_preamble || data_island_preamble}, {vsync, hsync}}; // ctrl3, ctrl2, ctrl1, ctrl0, vsync, hsync
                data_island_data[11:4] <= packet_data[8:1];
                data_island_data[3] <= cx != 0;
                data_island_data[2] <= packet_data[0];
                data_island_data[1:0] <= {vsync, hsync};
            end
        end
    end
endgenerate

// All logic below relates to the production and output of the 10-bit TMDS code.
logic [9:0] tmds_internal [NUM_CHANNELS-1:0] /* verilator public_flat */ ;
genvar i;
generate
    // TMDS code production.
     for (i = 0; i < NUM_CHANNELS; i++) 
    begin: tmds_gen
        tmds_channel #(.CN(i)) tmds_channel (.clk_pixel(clk_pixel_int), .video_data(video_data[i*8+7:i*8]), .data_island_data(data_island_data[i*4+3:i*4]), .control_data(control_data[i*2+1:i*2]), .mode(mode), .tmds(tmds_internal[i]));
    end
endgenerate

serializer #(.NUM_CHANNELS(NUM_CHANNELS)) serializer(.clk_pixel(clk_pixel_int), .clk_pixel_x5(clk_pixel_x5_int), .reset(reset), .tmds_internal(tmds_internal), .tmds(tmds), .tmds_clock(tmds_clock));
   
endmodule
