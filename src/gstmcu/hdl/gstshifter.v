//
// shifter.v
//
// Atari ST(E) shifter implementation for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2013-2015 Till Harbaum <till@harbaum.org>
// Copyright (c) 2019 Gyorgy Szombathelyi

// Video shifting engine based on chip decap by Jorge Cwik
//
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 

module gstshifter (
	input  clk32,
	input  ste,
	input  resb,

	// CPU/RAM interface
	input  CS,           // CMPCS
	input  [6:1] A,
	input  [15:0] DIN,
	output [15:0] DOUT,
	input  LATCH,
	input  RDAT_N,       // output enable for latched MDIN or shifter out -> DOUT
	input  WDAT_N,       // DIN  -> MDOUT
	input  RW,
	input  [15:0] MDIN,  // RAM input
	output [15:0] MDOUT, // RAM output
	// VIDEO
	output MONO_OUT,
	input  LOAD_N,       // DCYC_N
	input  DE,
	input  BLANK_N,
	output reg [3:0] R,
	output reg [3:0] G,
	output reg [3:0] B,

        output [1:0] SHMODE,

	// DMA SOUND
	input  SLOAD_N,
	output SREQ,
	output reg [7:0] audio_left,
	output reg [7:0] audio_right
);

// ---------------------------------------------------------------------------
// --------------------------- CPU/MEMORY BUS separation ---------------------
// ---------------------------------------------------------------------------

wire [15:0] mbus_in = CS ? s_dout : MDIN;
reg  [15:0] s_dout;

mlatch #(16) dout_l(clk32, 1'b0, 1'b0, LATCH, mbus_in, DOUT);

mlatch #(16) mdout_l(clk32, 1'b0, 1'b0, !WDAT_N, DIN, MDOUT);

// ---------------------------------------------------------------------------
// ------------------------------ VIDEO SHIFTER ------------------------------
// ---------------------------------------------------------------------------

// default video mode is 320x200
parameter DEFAULT_MODE = 2'd0;

assign MONO_OUT = mono;
// shiftmode register
/* verilator lint_off UNOPTFLAT */
reg [1:0] shmode;
/* verilator lint_on UNOPTFLAT */
wire mono  = (shmode == 2'd2);
wire mid   = (shmode == 2'd1);
wire low   = (shmode == 2'd0);
assign SHMODE = shmode;   // export for HDMI pixel clock generation
   
// 16 colors with 3*4 bits each (4 bits for STE, ST only uses 3 bits)
reg [3:0] palette_r[15:0];
reg [3:0] palette_g[15:0];
reg [3:0] palette_b[15:0];
reg       monocolor;

// STE-only registers
reg [3:0] pixel_offset;             // number of pixels to skip at begin of line

// ---------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------
// ---------------------------------------------------------------------------

always @(*) begin
	s_dout = 16'h0000;

	// read registers
	if(CS && RW) begin

		if(ste) begin
			if(A == 6'h32) s_dout = { 12'h000, pixel_offset };
		end

		// the color palette registers
		if(A[6:5] == 2'b10) begin
			s_dout[ 3:0] = palette_b[A[4:1]];
			s_dout[ 7:4] = palette_g[A[4:1]];
			s_dout[11:8] = palette_r[A[4:1]];

			// return only the 3 msb in non-ste mode
			if(!ste) begin
				s_dout[ 3] = 1'b0;
				s_dout[ 7] = 1'b0;
				s_dout[11] = 1'b0;
			end
		end

		// shift mode register
		if(A == 6'h30) s_dout = { 6'h00, shmode, 8'h00    };

		if(ste) begin
			// sound mode register
			if(A == 6'h10) s_dout[7:0] = { sndmode[2], 5'd0, sndmode[1:0] };
			// mircowire
			if(A == 6'h11) s_dout = mw_data_reg;
			if(A == 6'h12) s_dout = mw_mask_reg;
		end
	end
end

// ---------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------
// ---------------------------------------------------------------------------
wire write = CS_d & ~CS & ~RW;
reg CS_d;
always @(posedge clk32) CS_d <= CS;

always @(posedge clk32) begin
	reg[1:0] shmode_d;
	if(!resb) begin
		shmode_d <= DEFAULT_MODE;   // default video mode 2 => mono

		// disable STE hard scroll features
		pixel_offset <= 4'h0;

		monocolor <= 1'b1;
        
`ifdef SET_DEFAULT_PALETTE
	   // the palette registers are not set by default and the atari sets
	   // them at boot time. For simulation or testing without working
	   // CPU it can be useful to be able to set a color palette automatically
           { palette_r[ 0], palette_g[ 0], palette_b[ 0] } <= 12'h777;
           { palette_r[ 1], palette_g[ 1], palette_b[ 1] } <= 12'h700;
           { palette_r[ 2], palette_g[ 2], palette_b[ 2] } <= 12'h070;
           { palette_r[ 3], palette_g[ 3], palette_b[ 3] } <= 12'h770;
           { palette_r[ 4], palette_g[ 4], palette_b[ 4] } <= 12'h007;
           { palette_r[ 5], palette_g[ 5], palette_b[ 5] } <= 12'h707;
           { palette_r[ 6], palette_g[ 6], palette_b[ 6] } <= 12'h077;
           { palette_r[ 7], palette_g[ 7], palette_b[ 7] } <= 12'h555;
           { palette_r[ 8], palette_g[ 8], palette_b[ 8] } <= 12'h333;
           { palette_r[ 9], palette_g[ 9], palette_b[ 9] } <= 12'h733;
           { palette_r[10], palette_g[10], palette_b[10] } <= 12'h373;
           { palette_r[11], palette_g[11], palette_b[11] } <= 12'h773;
           { palette_r[12], palette_g[12], palette_b[12] } <= 12'h337;
           { palette_r[13], palette_g[13], palette_b[13] } <= 12'h737;
           { palette_r[14], palette_g[14], palette_b[14] } <= 12'h377;
           { palette_r[15], palette_g[15], palette_b[15] } <= 12'h000;
`endif
           
	end else begin
		// a bit of delay to the shmode register write - Closure demo likes it
		shmode <= shmode_d;
		// write registers as D Flip-flops
		if(write) begin

			// writing special STE registers
			if(ste) begin
				// sound mode register
				if(A == 6'h10) sndmode <= { MDOUT[7], MDOUT[1:0] };
				if(A == 6'h32) pixel_offset <= MDOUT[3:0];
			end
			// make msb writeable if MiST video modes are enabled
			if(A == 6'h30) shmode_d <= MDOUT[9:8];
		end

		// the color palette registers, always write bit 3 with zero if not in 
		// ste mode as this is the lsb of ste
		// Palette registers are gated latches
		if (CS & ~RW) begin
			if(A[6:5] == 2'b10) begin
				if (A[4:1] == 4'h0) monocolor <= MDOUT[0];
				if(!ste) begin
					palette_r[A[4:1]] <= { 1'b0, MDOUT[10:8] };
					palette_g[A[4:1]] <= { 1'b0, MDOUT[ 6:4] };
					palette_b[A[4:1]] <= { 1'b0, MDOUT[ 2:0] };
				end else begin
					palette_r[A[4:1]] <= MDOUT[11:8];
					palette_g[A[4:1]] <= MDOUT[ 7:4];
					palette_b[A[4:1]] <= MDOUT[ 3:0];
				end
			end

		end
	end
end

// ---------------------------------------------------------------------------
// -------------------------- video signal generator -------------------------
// ---------------------------------------------------------------------------
// clock enable divider
reg  [1:0] t;
always @(posedge clk32, negedge resb)
	if (!resb) t <= 2'b01; else t <= t + 1'd1;

wire pclk_en = mono?1'b1:mid?~t[0]:low?t==2'b01:1'b0;

wire reload;

wire [3:0] color_index;

`ifdef VERILATOR
wire pixClk = mono?clk32:mid?t[0]:low?t[1]:1'b0;

shifter_video_async shifter_video_async (
    .clk32 (clk32),
    .nReset (resb),
    .pixClk (pixClk),
    .DE(DE),
    .LOAD(LOAD_N),
    .rez(shmode),
    .monocolor(~monocolor),
    .DIN(MDIN),
    .color_index()
);
`endif

shifter_video shifter_video (
    .clk32 (clk32),
    .nReset (resb),
    .pixClkEn(pclk_en),
    .DE(DE),
    .LOAD(LOAD_N),
    .rez(shmode),
    .monocolor(~monocolor),
    .scroll(|pixel_offset),
    .DIN(MDIN),
    .Reload(reload),
    .color_index(color_index)
);

// ----------------------- monochrome video signal ---------------------------
wire [3:0] mono_rgb = { 4{shifted_color_index[0] ^ monocolor} };

// ------------------------- colour video signal -----------------------------

// For ST compatibility reasons the STE has the color bit order 0321. This is 
// handled here
reg  [3:0] color_addr, color_addr_d, color_addr_d2;
reg  [3:0] color_r_pal;
wire [3:0] color_r = { color_r_pal[2:0], color_r_pal[3] };
reg  [3:0] color_g_pal;
wire [3:0] color_g = { color_g_pal[2:0], color_g_pal[3] };
reg  [3:0] color_b_pal;
wire [3:0] color_b = { color_b_pal[2:0], color_b_pal[3] };

// --------------- de-multiplex color and mono into one vga signal -----------
wire [3:0] stvid_r = mono?mono_rgb:color_r;
wire [3:0] stvid_g = mono?mono_rgb:color_g;
wire [3:0] stvid_b = mono?mono_rgb:color_b;

always @(posedge clk32) begin
	if (resb) begin
		if (pclk_en) begin
			color_addr <= mid ? { 2'b00, shifted_color_index[1:0] } : shifted_color_index;
			color_addr_d <= color_addr;
			color_addr_d2 <= color_addr_d;
			color_r_pal <= palette_r[color_addr_d2];
			color_g_pal <= palette_g[color_addr_d2];
			color_b_pal <= palette_b[color_addr_d2];

			// drive video output
			R <= (BLANK_N | mono)?stvid_r:4'b0000;
			G <= (BLANK_N | mono)?stvid_g:4'b0000;
			B <= (BLANK_N | mono)?stvid_b:4'b0000;
		end
	end
end


// ---------------------------------------------------------------------------
// --------------------------- STE hard scroll shifter -----------------------
// ---------------------------------------------------------------------------

// shifted data
reg [14:0] ste_shifted_0, ste_shifted_1, ste_shifted_2, ste_shifted_3;
wire [3:0] shifted_color_index;
reg  [5:0] pix_cntr;
reg        pix_cntr_en;

always @(posedge clk32) begin
	if (pclk_en) begin
		ste_shifted_0 <= { color_index[0], ste_shifted_0[14:1] };
		ste_shifted_1 <= { color_index[1], ste_shifted_1[14:1] };
		ste_shifted_2 <= { color_index[2], ste_shifted_2[14:1] };
		ste_shifted_3 <= { color_index[3], ste_shifted_3[14:1] };

		// mask out "partial" columns at the beginning and at the end when hard scroll is used
		if ((pix_cntr == 6'h0 && !DE) || (pix_cntr == 6'hf && DE)) pix_cntr_en <= 1'b0;
		else if (pix_cntr_en) if (DE) pix_cntr <= pix_cntr + 1'd1; else pix_cntr <= pix_cntr - 1'd1;
		if (pix_cntr == 6'h0 &&  DE && reload) pix_cntr_en <= 1'b1;
		if (pix_cntr == 6'hf && !DE && reload) begin
			pix_cntr_en <= 1'b1;
			if (mid) pix_cntr <= 6'h1f; // 31 pixels after the last reload
			if (mono) pix_cntr <= 6'h3f; // 63 pixels after the last reload
		end
	end
end

assign shifted_color_index[0] = (pixel_offset == 4'd0) ? color_index[0] : (((pix_cntr == 6'hf && DE) || (pix_cntr != 6'h0 && !DE)) ? ste_shifted_0[pixel_offset - 1'd1] : 1'b0);
assign shifted_color_index[1] = (pixel_offset == 4'd0) ? color_index[1] : (((pix_cntr == 6'hf && DE) || (pix_cntr != 6'h0 && !DE)) ? ste_shifted_1[pixel_offset - 1'd1] : 1'b0);
assign shifted_color_index[2] = (pixel_offset == 4'd0) ? color_index[2] : (((pix_cntr == 6'hf && DE) || (pix_cntr != 6'h0 && !DE)) ? ste_shifted_2[pixel_offset - 1'd1] : 1'b0);
assign shifted_color_index[3] = (pixel_offset == 4'd0) ? color_index[3] : (((pix_cntr == 6'hf && DE) || (pix_cntr != 6'h0 && !DE)) ? ste_shifted_3[pixel_offset - 1'd1] : 1'b0);

//////////////////////////////////////////////////////////////////////////
//////////////////////////////// DMA SOUND ///////////////////////////////
//////////////////////////////////////////////////////////////////////////

wire clk_8_en = (t == 0);

reg [2:0] sndmode;

// micro wire
reg [15:0] mw_data_in;
reg [15:0] mw_data_reg, mw_mask_reg;
reg  [6:0] mw_cnt;   // micro wire shifter counter

// micro wire outputs
reg mw_clk;
reg mw_data;
reg mw_done;

reg mw_data_write, mw_mask_write;

// ----------- micro wire interface -----------
always @(posedge clk32) begin
	if(!resb) begin
		mw_cnt <= 7'h00;        // no micro wire transfer in progress
	end else begin
		if (clk_8_en) begin
			// writing the data register triggers the transfer
			if(mw_data_write || mw_cnt != 0) begin

				// decrease shift counter. Do this before the register write as
				// register write has priority and should reload the counter
				if(mw_cnt != 0)
					mw_cnt <= mw_cnt - 7'd1;

				if(mw_data_write) begin
					// first bit is evaluated imediately
					mw_data_reg <= { mw_data_in[14:0], 1'b0 };
					mw_data <= mw_data_in[15];
					mw_cnt <= 7'h7f;
				end else if(mw_cnt[2:0] == 3'b000) begin
					// send/shift next bit every 8 clocks -> 1 MBit/s
					mw_data_reg <= { mw_data_reg[14:0], 1'b0 };
					mw_data <= mw_data_reg[15];
				end

				// rotate mask on first access and on every further 8 clocks
				if(mw_data_write || (mw_cnt[2:0] == 3'b000)) begin
					mw_mask_reg <= { mw_mask_reg[14:0], mw_mask_reg[15]};
					// notify client of valid bits
					mw_clk <= mw_mask_reg[15];
				end

				// indicate end of transfer
				mw_done <= (mw_cnt == 7'h01);
			end

			// mask register write
			if(mw_mask_write) begin
				mw_mask_reg <= mw_data_in;
				// stop transfer when the mask register is written during transfer
				// Systematic Error demo relies on it
				mw_cnt <= 0;
			end

			mw_data_write <= 0;
			mw_mask_write <= 0;
		end

		// latch write data
		if (write) begin
			mw_data_in <= MDOUT;
			mw_data_write <= A == 6'h11;
			mw_mask_write <= A == 6'h12;
		end
	end
end

// ---------------------------------------------------------------------------
// ----------------------- audio  clock generation ---------------------------
// ---------------------------------------------------------------------------

// base clock is 8MHz/160 (32MHz/640)
reg       a2base;
reg [9:0] a2base_cnt;
reg       a2base_en;

always @(posedge clk32) begin
	a2base_cnt <= a2base_cnt + 1'd1;
	if(a2base_cnt == 639) a2base_cnt <= 0;
	a2base_en <= (a2base_cnt == 0);
end

// generate current audio clock
reg [2:0] aclk_cnt;
always @(posedge clk32) if (a2base_en) aclk_cnt <= aclk_cnt + 3'd1;

reg aclk_en;
always @(posedge clk32) begin
	aclk_en <=  a2base_en & (
	            (sndmode[1:0] == 2'b11)?a2base_en:             // 50 kHz
	           ((sndmode[1:0] == 2'b10)?(aclk_cnt[0] == 0):    // 25 kHz
	           ((sndmode[1:0] == 2'b01)?(aclk_cnt[1:0] == 0):  // 12.5 kHz
	            (aclk_cnt == 0))));                         // 6.25 kHz
end

// ---------------------------------------------------------------------------
// --------------------------------- audio fifo ------------------------------
// ---------------------------------------------------------------------------

// This type of fifo can actually never be 100% full. It contains at most
// 2^n-1 words. A n=2 buffer can thus contain at most 3 words which at 50kHz
// stereo means that the buffer needs to be reloaded at 16.6kHz. Reloading
// happens in hde1 at 15.6Khz. Thus a n=2 buffer is not sufficient..

localparam FIFO_ADDR_BITS = 3;    // four words
localparam FIFO_DEPTH = (1 << FIFO_ADDR_BITS);
reg [15:0] fifo [FIFO_DEPTH-1:0];
reg [FIFO_ADDR_BITS-1:0] writeP, readP;
wire fifo_empty = (readP == writeP);
wire fifo_full = (readP == (writeP + 2'd1));

assign SREQ = !fifo_full;

// ---------------------------------------------------------------------------
// -------------------------------- audio engine -----------------------------
// ---------------------------------------------------------------------------

reg bytesel;   // byte-in-word toggle flag
wire [15:0] fifo_out = fifo[readP];
wire [7:0] mono_byte = (!bytesel)?fifo_out[15:8]:fifo_out[7:0];

// empty the fifo at the correct rate
always @(posedge clk32) begin
	if(!resb) begin
		readP <= 0;
	end else if (aclk_en) begin
		// audio data in fifo? play it!
		if(!fifo_empty) begin
			if(!sndmode[2]) begin
				audio_left  <= fifo_out[15:8] + 8'd128;   // high byte == left channel
				audio_right <= fifo_out[ 7:0] + 8'd128;   // low byte == right channel
			end else begin
				audio_left  <= mono_byte + 8'd128;
				audio_right <= mono_byte + 8'd128;
				bytesel <= !bytesel;
			end
			// increase fifo read pointer every sample in stereo mode and every
			// second sample in mono mode
			if(!sndmode[2] || bytesel) readP <= readP + 1'd1;
		end
	end
end

always @(posedge clk32) begin
	reg sload_d;

	if (!resb) begin
		writeP <= 0;
	end else begin
		sload_d <= SLOAD_N;
		if (~sload_d & SLOAD_N) begin
			// data was requested when fifo wasn't full, so don't have to check it here
			fifo[writeP] <= MDIN;
			writeP <= writeP + 1'd1;
		end
	end
end

endmodule
