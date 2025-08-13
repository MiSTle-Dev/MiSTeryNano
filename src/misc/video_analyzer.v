//
// video_analyzer.v
//
// try to derive video parameters from hs/vs/de
//

module video_analyzer 
(
 // system interface
 input		  clk,
 input		  hs,
 input		  vs,
 input		  de,

 input		  wide,
 output reg [1:0] mode, // 0=ntsc, 1=pal, 2=mono
 output reg	  vreset
);
   

// generate a reset signal in the upper left corner of active video used
// to synchonize the HDMI video generation to the Atari ST
reg vsD, hsD;
reg [12:0] hcnt;    // signal ranges 0..2047
reg [12:0] hcntL;
reg [9:0] vcnt;    // signal ranges 0..313
reg [9:0] vcntL;
reg changed;
reg wideL;   
   
always @(posedge clk) begin
    // ---- hsync processing -----
    hsD <= hs;

    // make sure changes in wide/normal also trigger
    // a vreset
    if(wide != wideL) begin
       changed <= 1'b1;
       wideL <= wide;
    end

    // begin of hsync, falling edge
    if(!hs && hsD) begin
        // check if line length has changed during last cycle
        hcntL <= hcnt;
        if(hcntL != hcnt)
            changed <= 1'b1;

        hcnt <= 0;
    end else
        hcnt <= hcnt + 13'd1;

    if(!hs && hsD) begin
       // ---- vsync processing -----
       vsD <= vs;
       // begin of vsync, falling edge
       if(!vs && vsD) begin
          // check if image height has changed during last cycle
          vcntL <= vcnt;
          if(vcntL != vcnt)
             changed <= 1'b1;

          vcnt <= 0;
	  
	  // check for PAL/NTSC values
	  if(vcnt == 10'd312 && hcntL == 13'd2047) mode <= 2'd1;  // PAL
	  if(vcnt == 10'd262 && hcntL == 13'd2031) mode <= 2'd0;  // NTSC

	  // check for MONO
	  if(vcnt == 10'd500 && hcntL == 13'd895)  mode <= 2'd2;  // MONO
	  
       end else
         vcnt <= vcnt + 10'd1;
    end

   // the reset signal is sent to the HDMI generator. On reset the
   // HDMI re-adjusts its counters to the start of the visible screen
   // area
   
   vreset <= 1'b0;
   // account for back porches to adjust image position within the HDMI frame
   if( (hcnt == (wide?204:244) && vcnt == 36 && changed && mode == 2'd2) ||
       (hcnt == (wide?112:152) && vcnt == 28 && changed && mode == 2'd1) ||
       (hcnt == (wide?112:152) && vcnt == 18 && changed && mode == 2'd0) ) begin
      vreset <= 1'b1;
      changed <= 1'b0;
   end
end


endmodule
