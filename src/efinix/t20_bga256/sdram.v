//
// sdram.v
//
// sdram controller implementation for the Insigis NDS36PT5-20ET
// 256Mb SDRAM on the Efinix Trion T20 BGA256 dev board
// http://insignis-tech.com/download/145
//
// Copyright (c) 2024 Till Harbaum <till@harbaum.org> 
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
//

// MiSTery Atari ST ram timing
// 32MHz cycle      6 7 0 1 2 3 4 5 6 7 0 1 2
// ram_cnt                  0 1 2 3 4 5 6
//                  _________           _____
// RAS/WE/REF                \_________/
//                          _____           _
// CAS              ???????/     \_________/
//                      _______________ 
// ADDR             ???X_______________X?????
//                            _______________
// DIN              ?????????X_______________


// on efinix T20 addr comes very late and isn't stable
// at the falling edge of ras

module sdram (
	output		  sd_clk,      // sd clock
	output		  sd_cke,      // clock enable
	inout [15:0] sd_data,  // 16 bit bidirectional data bus
	output reg [12:0] sd_addr, // 13 bit multiplexed address bus
	output reg [1:0]  sd_dqm,  // two byte masks
	output reg [1:0]  sd_ba,   // four banks
	output		  sd_cs,       // a single chip select
	output		  sd_we,       // write enable
	output		  sd_ras,      // row address select
	output		  sd_cas,      // column address select

	// cpu/chipset interface
	input		  clk,         // sdram is accessed at 32MHz
	input		  reset_n,     // init signal after FPGA config to initialize RAM

	output		  ready,       // ram is ready and has been initialized
	input		  refresh,     // chipset requests a refresh cycle
	input [15:0]	  din,         // data input from chipset/cpu
	output [15:0] dout,
	input [21:0]	  addr,        // 22 bit word address
	input [1:0]	  ds,          // upper/lower data strobe
	input		  cs,          // cpu/chipset requests read/wrie
	input		  we           // cpu/chipset requests write
);

// efinity doesn't like inout registers
reg [15:0] sd_data_reg;   
assign sd_data = sd_data_reg;   
   
assign sd_clk = !clk;
assign sd_cke = reset_n;
   
localparam RASCAS_DELAY   = 3'd1;   // tRCD=15ns -> 1 cycle@32MHz = 32.25ns
localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

// mode bits        12:10         9          8:7        6:4          3            2:0
localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

// The state machine runs at 32Mhz synchronous to the sync signal.
localparam STATE_IDLE      = 3'd0;                      // 0 first state in cycle
localparam STATE_CMD_CONT  = STATE_IDLE + RASCAS_DELAY; // 1 command can be continued
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 1; // 4
localparam STATE_LAST      = 3'd6;  // 14 last state in cycle, returns to idle
   
// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

reg [3:0] state;
reg [4:0] init_state;

// wait 1ms (32 8Mhz cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
assign ready = !(|init_state);
   
// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;  // cs only
localparam CMD_ACTIVE          = 4'b0011;  // cs+ras
localparam CMD_READ            = 4'b0101;  // cs+cas
localparam CMD_WRITE           = 4'b0100;  // cs+cas+we
localparam CMD_BURST_TERMINATE = 4'b0110;  // cs+we
localparam CMD_PRECHARGE       = 4'b0010;  // cs+ras+we
localparam CMD_AUTO_REFRESH    = 4'b0001;  // cs+ras+cas
localparam CMD_LOAD_MODE       = 4'b0000;  // cs+ras+cas+we

reg [3:0] sd_cmd;   // current command sent to sd ram
// drive control signals according to current command
assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

assign dout = sd_data;
// assign sd_data = (cs && we) ? din : 16'bzzzz_zzzz_zzzz_zzzz;

always @(posedge clk) begin
   reg csD, csD2;
   reg [8:0] addrD;   
   reg	     weD;
   reg	     ram_cs;
   
   csD <= cs;
   csD2 <= csD;

   // start write access one cycle later. This needs some
   // more investigation as to why this is needed. Not clear
   // if this is due to the different ram chip or due to the
   // fpga
   ram_cs <= we?(csD && !csD2):(cs && !csD);   
   
   // init state machines runs once reset ends
   if(!reset_n) begin
      sd_cmd <= CMD_INHIBIT;      
      init_state <= 5'h1f;
      state <= STATE_IDLE;      
      sd_dqm <= 2'b00;
      sd_ba <= 2'b00;	    	 
   end else begin
      sd_cmd <= CMD_NOP;  // default: idle

      if(init_state != 0)
        state <= state + 3'd1;
      
      if((state == 3'd7) && (init_state != 0))
        init_state <= init_state - 5'd1;
   
      if(init_state != 0) begin
	 // initialization takes place at the end of the reset
	 if(state == STATE_IDLE) begin
	    if(init_state == 13) begin
	       sd_cmd <= CMD_PRECHARGE;
	       sd_addr[10] <= 1'b1;      // precharge all banks
	    end
	    
	    if(init_state == 2) begin
	       sd_cmd <= CMD_LOAD_MODE;
	       sd_addr <= MODE;
	    end
	    
	 end
      end else begin
	 // normal operation, start on ... 
	 if(state == STATE_IDLE) begin
            // ... rising edge of cs
            if(ram_cs) begin
               if(!refresh) begin
		  // RAS phase. If enabled during write causes noise
		  sd_cmd <= CMD_ACTIVE;
		  sd_addr <= addr[21:9];  // 4 Megawords = 8 Megabytes per bank
		  sd_ba <= 2'b00;         // use one of the four banks only
		  sd_dqm <= we?ds:2'b00;
               end else
	         sd_cmd <= CMD_AUTO_REFRESH;
	       
               state <= 3'd1;
               addrD <= addr[8:0];	     
	       weD <= we;
            end
	 end else begin
            // always advance state unless we are in idle state
            state <= state + 3'd1;
	    
            // -------------------  cpu/chipset read/write ----------------------

            // CAS phase 
            if(state == STATE_CMD_CONT) begin
               sd_cmd <= weD?CMD_WRITE:CMD_READ;
	       // A[12:9] 0010 / A10 = 1 (read/write and auto precharge)
               sd_addr <= { 4'b0010, addrD };  // 12:9 / 8:0 = 4+9
	       if(weD) begin 
		      sd_data_reg <= din;
	       end
            end
	    
	    // disable data output driver asap
            if(state == STATE_CMD_CONT+1)
	      sd_data_reg <= 16'hzzzz;
	    
	    // return to idle state
            if(state == STATE_LAST)
	      state <= 0;	 
	 end
      end
   end
end
   
endmodule
