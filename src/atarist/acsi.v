// acsi.v
//
// Atari ST ACSI implementation for the MIST board
// https://github.com/mist-devel/mist-board
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
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

module acsi (
    // clocks and system interface
	input 			  clk,
	input 			  clk_en,
	input 			  reset,

	input [7:0] 	  enable,
	input [63:0] 	  img_size [2],

	// SD card interface
	output reg [1:0]  data_rd_req, // request read from sd card
	output reg [1:0]  data_wr_req, // request write to sd card
	output reg [31:0] data_lba,   // lba requested
	output reg [15:0] data_length, // length requested
	input 			  data_busy, // sd card has accepted request and now loads sector
	input 			  data_done, // sd card ready in reply to req
	input 			  dma_done, // DMA transfer finished
	input 			  data_next, // DMA requests another sector to be tranferred
	     
    // cpu interface
	input 			  cpu_a1,
	input 			  cpu_sel,
	input 			  cpu_rw,
	input [7:0] 	  cpu_din,
	output [7:0] 	  cpu_dout,

    // ACSI command reply output to be written into DMA FIFO
	output [15:0] 	  reply_data,
	output 			  reply_req,
	input 			  reply_ack,
			 
	output reg 		  irq,

    output [1:0]      leds
);

reg [15:0] led_counter [2];
assign leds = { |led_counter[1], |led_counter[0] };

reg cpu_selD;
always @(posedge clk) if (clk_en) cpu_selD <= cpu_sel;
wire cpu_req = ~cpu_selD & cpu_sel;

// Total number of command bytes:
// cmd 0..1f  -> 6 
// cmd 20..5f -> 10
// cmd 80..9f -> 16
// cmd a0..bf -> 12

wire [7:0] cmd_code = cmd_parameter[0];
wire [3:0] parms =
	((cmd_code >= 8'h00)&&(cmd_code <= 8'h1f))?4'd5:
	((cmd_code >= 8'h20)&&(cmd_code <= 8'h5f))?4'd9:
	((cmd_code >= 8'h80)&&(cmd_code <= 8'h9f))?4'd15:
	4'd11;
   
reg [2:0] target;
reg [3:0] byte_counter;
reg [7:0] cmd_parameter [15:0];
reg err;

// ASC = additional sense code for Sense Key 0x05 (Illegal Request)
// 0x0e Invalid Field
// 0x1a Parameter Length Error
// 0x20 Invalid Command
// 0x21 Invalid Element
// 0x24 Invalid Field in CDB
// 0x25 Logical Unit Not Supported
// 0x26 Invalid Field in Parameters
reg [7:0] asc [2];

// acsi always returns dma status on cpu_read
// status byte TTTEEEEE 
// TTT = target
// EEEEE
//   Bit 4: reserved, always 0
//   Bit 3: busy
//   Bit 2: condition met, always 0
//   Bit 1: check bit (1 == error)
//   Bit 0: reserved, always 0
// assign cpu_dout = { target, 3'b000, err, 1'b0 };
assign cpu_dout = { 3'b000, 3'b000, err, 1'b0 };

// ======================= handle SCSI replies ============================

// some commands can address subunits (LUNs) which we don't support
wire [2:0] lun = cmd_parameter[1][7:5];

// lba parameter for read(6), write(6) and seek(6)
wire [31:0] lba6 = { 10'd0, cmd_parameter[1][4:0], 
        cmd_parameter[2], cmd_parameter[3] };

// length parameter for read(6), write(6) and seek(6)
wire [15:0] length6 = { 8'h00, cmd_parameter[4] };

// lba parameter for read(10), write(10) and seek(10)
wire [31:0] lba10 = { cmd_parameter[2], cmd_parameter[3],
        cmd_parameter[4], cmd_parameter[5] };     

// length parameter for read(10), write(10) and seek(10)
wire [15:0] length10 = { cmd_parameter[7], cmd_parameter[8] };

// lba and length matching the current command
wire [31:0] lba = (cmd_code[7:4] == 4'h2)?lba10:lba6;
wire [15:0] length = (cmd_code[7:4] == 4'h2)?length10:length6;
  
// This is 16 bit since the MiSTery core's DMA uses 
// 16 bit FIFOs which we directly write data into
assign reply_data = (cmd_code == 8'h03)?request_sense_reply_data:
					(cmd_code == 8'h12)?inquiry_reply_data:
					(cmd_code == 8'h1a)?mode_sense_reply_data:
					(cmd_code == 8'h25)?read_capacity_reply_data:
					(cmd_code == 8'ha0)?report_luns_reply_data:
					16'h0000;

// reply word counter   
localparam REPLY_IDLE  = 7'd127;  
localparam REPLY_START = 7'd0;  
reg [6:0] reply_cnt;
assign reply_req = (reply_cnt != REPLY_IDLE);   

// we have two sizes to care for: The size that may be specified in the
// request and the actual reply size the device can offer. We return whatever
// is lower

wire [6:0] cmd_req_len = 
		   (cmd_code == 8'h03)?cmd_parameter[4][7:1]:  // request sense
		   (cmd_code == 8'h12)?cmd_parameter[4][7:1]:  // inquiry
		   7'd0;   
   
// command reply length in 16 words. read and write a handled
// seperately
wire [6:0] cmd_max_reply_len =
		   (cmd_code == 8'h03)?7'd9:  // request sense
		   (cmd_code == 8'h12)?7'd48: // inquiry
		   (cmd_code == 8'h1a)?7'd8:  // mode sense
		   (cmd_code == 8'h25)?7'd4:  // read capacity
		   (cmd_code == 8'ha0)?7'd8:  // report luns
		   7'd0;   

// if a request length was given and if it's smaller than the reply, then
// only transfer the requested number of words. Otherwise transfer the
// max reply len
wire [6:0] cmd_reply_len =
		   ((cmd_req_len != 0) && (cmd_req_len < cmd_max_reply_len))?cmd_req_len:
		   cmd_max_reply_len;   
		   
// ------------------------ Request Sense ----------------------------

wire current_target = target[0];
wire [15:0] request_sense_reply_data = 
            (reply_cnt == 0)?{1'b0, 7'h70, 8'h00 }:
			((reply_cnt == 1) && (asc[current_target] != 0))?16'h0500:
			(reply_cnt == 3)?16'd11:                        // 18-7
			(reply_cnt == 6)?{ asc[current_target], 8'h00 }:
			16'h0000;

// ------------------------ Report LUNs ----------------------------
wire [15:0] report_luns_reply_data = 
            (reply_cnt == 1)?16'h0008:   // LUN list length = 8 bytes
			16'h0000;

// ------------------------ Inquiry ----------------------------

// string sent in inquiry reply bytes 8 to 36
wire [7:0] inquiry_str [28];
assign inquiry_str = "MiSTery Harddisk Image  4711";

wire [15:0] inquiry_reply_data =
		   ((reply_cnt == 0) && (lun != 3'd0))?16'h7f00:
		   (reply_cnt == 1)?16'h0100:                        // SCSI-1
		   (reply_cnt == 2)?{cmd_parameter[4]-8'd5,8'h00}:   // length
		   (reply_cnt >= 4 && reply_cnt < 18)?{ inquiry_str[2*(reply_cnt-4)],
												inquiry_str[2*(reply_cnt-4)+1]}:
		   16'h0000;

// ------------------------ Read Capacity ----------------------------
wire [63:0] current_image_size = img_size[current_target];
wire [31:0] current_block_size = current_image_size[40:9];
wire [31:0] max_block_number = current_block_size - 32'd1;   
   
wire [15:0] read_capacity_reply_data = 
			(reply_cnt == 0)?max_block_number[31:16]:   // address of last block
			(reply_cnt == 1)?max_block_number[15:0]:
			(reply_cnt == 3)?16'd512:                     // block size in bytes
			16'h0000;
			
// ------------------------ Mode Sense(6) ----------------------------
wire [15:0] mode_sense_reply_data = 
			(reply_cnt == 0)?16'h000e:
			(reply_cnt == 1)?16'h0008:   // size of extent descriptor list
			(reply_cnt == 2)?current_block_size[31:16]:
			(reply_cnt == 3)?current_block_size[15:0]:
			(reply_cnt == 5)?16'd512:    // block size in bytes
			16'h0000;
			
// read and write commands have a lun field
// request sense actually also contains the LUN, but reports
// the missing LUN by itself
wire 	cmd_has_lun =		
		(cmd_code == 8'h00) ||   // test unit ready
		(cmd_code == 8'h08) ||   // read(6)
		(cmd_code == 8'h0b) ||   // seek(6)
		(cmd_code == 8'h28) ||   // read(10)
		(cmd_code == 8'h2b) ||   // seek(10)
		(cmd_code == 8'h0a) ||   // write(6)
		(cmd_code == 8'h2a);     // write(10)   

reg	ignore_a1;
   
// CPU write interface
always @(posedge clk) begin
   if(reset) begin
      target <= 3'd0;
      irq <= 1'b0;
      data_rd_req <= 2'b00;
      data_wr_req <= 2'b00;
	  reply_cnt <= REPLY_IDLE;	  
      led_counter[0] <= 16'd0;
      led_counter[1] <= 16'd0;
	  ignore_a1 <= 1'b0;
	  byte_counter <= 4'd15;
   end else begin // if (reset)
      if(led_counter[0]) led_counter[0] <= led_counter[0] - 16'd1;
      if(led_counter[1]) led_counter[1] <= led_counter[1] - 16'd1;

	  if(reply_cnt != REPLY_IDLE) begin
		 if(reply_ack) begin
			if(reply_cnt < cmd_reply_len) begin
			   reply_cnt <= reply_cnt + 7'd1;
			end else begin
  			   reply_cnt <= REPLY_IDLE;
			   irq <= 1'b1;   // set acsi irq to signal end of transmission
			   asc[current_target] <= 8'h00;
			end
		 end
	  end
      	  
      // SD card has delivered data to DMA
      if(data_busy) begin
		 data_rd_req <= 2'b00;
		 data_wr_req <= 2'b00;
	  end
      
      if(data_next) begin
		 // check if a read or write is to be continued		 
		 // target can only be 0 or 1
		 if(cmd_code[3:0] == 4'h8)
		   data_rd_req[current_target] <= 1'b1;
		 
		 if(cmd_code[3:0] == 4'ha)
		   data_wr_req[current_target] <= 1'b1;		 
		 
		 // request next sector
		 data_lba <= data_lba + 32'd1;	 
 		 data_length <= data_length - 16'd1;							   
      end
      
      // entire DMA transfer is done
      if(dma_done) begin
         irq <= 1'b1;	 
         asc[current_target] <= 8'h00;		
      end
	  
      // cpu is accessing acsi bus -> clear acsi irq
      if(clk_en && cpu_req)
		irq <= 1'b0;
      
      // acsi register write access
      if(clk_en && cpu_req && !cpu_rw) begin
		 if(!cpu_a1 && !ignore_a1) begin
			// a1 == 0 -> first command byte
			target <= cpu_din[7:5];
            err <= 1'b0;
					
			// allow ACSI target 0 and 1 only
			// check if this acsi device is enabled
			if(cpu_din[7:5] < 2 && enable[cpu_din[7:5]] == 1'b1) begin
                irq <= 1'b1;

                // icd command?
                if(cpu_din[4:0] == 5'h1f)
                    byte_counter <= 3'd0;   // next byte will contain first command byte
                else begin
                    cmd_parameter[0] <= { 3'd0, cpu_din[4:0] };
                    byte_counter <= 3'd1;   // next byte will contain second command byte
                end
			   
			   // ignore a1 after the first command byte has been written
			   // Some drivers seem to rely on this like e.g. the ppera one
			   ignore_a1 <= 1'b1;
			end else
			  ignore_a1 <= 1'b0;
			  
		 end else begin			
			ignore_a1 <= 1'b0;
			
			// further bytes
			cmd_parameter[byte_counter] <= cpu_din;
			if(byte_counter != 4'd15)
			  byte_counter <= byte_counter + 3'd1;
			
			// check if this acsi device is enabled
			if(enable[target] == 1'b1) begin
			   // auto-ack first 5 bytes, 6 bytes in case of icd command
			   if(byte_counter < parms)
                 irq <= 1'b1;		  
			   else begin
                  // command complete

                  // check for sector limits of read, write and seek
                  if((cmd_code == 8'h08 || cmd_code == 8'h0a || cmd_code == 8'h0b ||
                      cmd_code == 8'h28 || cmd_code == 8'h2a || cmd_code == 8'h2b) &&
                      (lba >= current_block_size)) begin
                    // trying to access a block outside the limits
                    err <= 1'b1;
                    irq <= 1'b1;		  
                    asc[current_target] <= 8'h21;   // invalid element
                  end else begin

                    // only lun 0 is supported for read/write
                    if ((lun == 3'd0) || !cmd_has_lun ) begin
                        case( cmd_code ) 
                            // prepare reply transmission from ACSI into DMA buffer
                            8'h00,   // test unit ready
                            8'h04,   // format
                            8'h0b,   // seek(6)
                            8'h12,   // inquiry(6)
                            8'h15,   // mode select(6)
                            8'h1a,   // mode sense(6)
                            8'h1b,   // start/stop unit
                            8'h25,   // read capacity(10)
                            8'h2b,   // seek(10)
                            8'ha0:   // report LUNs
                                reply_cnt <= REPLY_START;

                            // request sense
                            8'h03: begin
                                // this is special as request sense reports an
                                // unsuppoted LUN immediately
                                if(lun != 3'd0)
                                    asc[current_target] = 8'h25;
							
                                reply_cnt <= REPLY_START;
                            end
						  
                            // read(6) and read(10)
                            8'h08, 8'h28: begin
                                // target can only be 0 or 1
                                data_rd_req[current_target] <= 1'b1;
                                data_lba <= lba;
 							    data_length <= length;							   
                                led_counter[current_target] <= 16'hffff;
                            end
					   					   
                            // write(6) and write(10)
                            8'h0a, 8'h2a: begin
                                // trigger DMA read from RAM into fifo to write to
                                // device. target can only be 0 or 1
                                data_wr_req[current_target] <= 1'b1;
                                data_lba <= lba;
 							    data_length <= length;							   
                                led_counter[current_target] <= 16'hffff;
                            end
					   
                            // commands to be rejected incl.
                            // 3e read long(10)
                            // 46 get configuration
                            // 5a mode sense(10)
                            // 88 read(16)
                            // 8a write(16)
                            // 9e 10: read capacity(16), 11: read long(16)
                            // a8 read(12)
                            // aa write(12)
                            default: begin
                                err <= 1'b1;
                                irq <= 1'b1;		  
                                asc[current_target] <= 8'h20;   // command not supported
                            end
                         endcase
                      end else begin
                        // lun != 0, only lun 0 is supported
                        err <= 1'b1;
                        irq <= 1'b1;		  
                        asc[current_target] <= 8'h25;   // logical unit not supported
                      end
                  end
			   end
			end
		 end
      end
   end
end
   
endmodule // acsi

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:

