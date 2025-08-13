//
// fdc1772.v
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

module fdc1772 (
	input            clkcpu, // system cpu clock.
	input            clk8m_en,

	// external set signals
	input      [W:0] floppy_drive,
	input            floppy_side, 
	input            floppy_reset,
	output           floppy_step,
	input            floppy_motor,
	output           floppy_ready,

	// interrupts
	output reg       irq,
	output reg       drq, // data request

	input      [1:0] cpu_addr,
	input            cpu_sel,
	input            cpu_rw,
	input      [7:0] cpu_din,
	output reg [7:0] cpu_dout,

	// place any signals that need to be passed up to the top after here.
	input      [2:0] img_type,
	input      [W:0] img_mounted, // signaling that new image has been mounted
	input      [W:0] img_wp,      // write protect
	input            img_ds,      // double-sided image (for BBC Micro only)
	input     [31:0] img_size,    // size of image in bytes
	output reg[31:0] sd_lba,
	output reg [W:0] sd_rd,
	output reg [W:0] sd_wr,
	input            sd_ack,
	input      [8:0] sd_buff_addr,
	input      [7:0] sd_dout,
	output     [7:0] sd_din,
	input            sd_dout_strobe
);


parameter CLK_EN           = 16'd8000; // in kHz
parameter FD_NUM           = 2;    // number of supported floppies
parameter MODEL            = 2;    // 0 - wd1770, 1 - fd1771, 2 - wd1772, 3 = wd1773/fd1793
parameter EXT_MOTOR        = 1'b0; // != 0 if motor is controlled externally by floppy_motor
parameter INVERT_HEAD_RA   = 1'b0; // != 0 - invert head in READ_ADDRESS reply

localparam IMG_ARCHIE      = 0;
localparam IMG_ST          = 1;
localparam IMG_BBC         = 2; // SSD, DSD formats
localparam IMG_TI99        = 3; // V9T9 format
localparam IMG_BETA        = 4; // Beta Disk Interface (with TR-DOS)
localparam IMG_PLUSD_IMG   = 5; // PlusD, non-track interleaved

localparam W    = FD_NUM - 1;
localparam WIDX = $clog2(FD_NUM);

// -------------------------------------------------------------------------
// --------------------- IO controller image handling ----------------------
// -------------------------------------------------------------------------

reg   [5:0] fdn_spt[FD_NUM];     // sectors/track
reg   [9:0] fdn_gap_len[FD_NUM]; // gap len/sector
reg         fdn_doubleside[FD_NUM];
reg         fdn_hd[FD_NUM];
reg         fdn_ed[FD_NUM];
reg         fdn_fm[FD_NUM];
reg         fdn_present[FD_NUM];
reg   [1:0] fdn_sector_size_code[FD_NUM]; // sec size 0=128, 1=256, 2=512, 3=1024
reg         fdn_sector_base[FD_NUM];
reg   [2:0] fdn_type[FD_NUM];

reg  [12:0] image_sectors;
reg  [12:0] image_sps; // sectors/side
reg   [5:0] image_spt; // sectors/track
reg   [9:0] image_gap_len;
reg         image_doubleside;
wire        image_hd = img_size[20]; // >1MB
wire        image_ed = img_size[21]; // >2MB
reg         image_fm;
reg   [1:0] image_sector_size_code; // sec size 0=128, 1=256, 2=512, 3=1024
reg         image_sector_base; // number of first sector on track (archie 0, dos 1)

always @(*) begin
	image_sps = 0;
	case (img_type)
	IMG_ARCHIE: begin
		// archie, 1024 bytes/sector
		image_sector_size_code = 2'd3;
		image_sector_base = 0;
		image_fm = 0;
		image_sectors = img_size[22:10];
		image_doubleside = 1'b1;
		image_spt = image_hd ? 6'd10 : 6'd5;
		image_gap_len = 10'd220;
	end
	IMG_ST, IMG_PLUSD_IMG: begin
		// this block is valid for the .st format (or similar arrangement), 512 bytes/sector
		image_sector_size_code = 2'd2;
		image_sector_base = 1;

		image_fm = 0;
		image_sectors = img_size[21:9];
		image_doubleside = 1'b0;
		image_sps = image_sectors;
		if (image_sectors > (85*12)) begin
			image_doubleside = 1'b1;
			image_sps = image_sectors >> 1'b1;
		end
		if (image_ed) image_sps = image_sps >> 2'd2; else
		if (image_hd) image_sps = image_sps >> 1'd1;

		// spt : 9-12, tracks: 79-85
		case (image_sps)
			711,720,729,738,747,756,765   : image_spt = 6'd9;
			790,800,810,820,830,840,850   : image_spt = 6'd10;
			948,960,972,984,996,1008,1020 : image_spt = 6'd12;
			default : image_spt = 6'd11;
		endcase;

		if (image_ed) image_spt = image_spt << 2'd2; else
		if (image_hd) image_spt = image_spt << 2'd1;

		// SECTOR_GAP_LEN = BPT/SPT - (SECTOR_LEN + SECTOR_HDR_LEN) = 6250/SPT - (512+6)
		case (image_spt)
			6'd9, 6'd18, 6'd36: image_gap_len = 10'd176;
			6'd10,6'd20, 6'd40: image_gap_len = 10'd107;
			6'd11,6'd22, 6'd44: image_gap_len = 10'd50;
			default : image_gap_len = 10'd2;
		endcase;
	end
	IMG_BBC, IMG_TI99, IMG_BETA: begin
		// 256 bytes/sector single density (BBC SSD/DSD, TI99/4A, BETA Disk Interface)
		image_sector_size_code = 2'd1;
		image_sector_base = 0;
		image_fm = 1;
		if (img_type == IMG_BBC) begin
			image_spt = 10;
		end else if (img_type == IMG_TI99) begin
			image_spt = 9;
		end else begin
			image_sector_base = 1;
			image_spt = 16;
			image_fm = 0;
		end

		image_sectors = img_size[19:8];
		image_doubleside = img_ds;
		image_gap_len = 10'd50;
	end
	default: begin
		image_sector_size_code = 2'd0;
		image_sector_base = 0;
		image_fm = 0;
		image_sectors = 0;
		image_doubleside = 0;
		image_spt = 0;
		image_gap_len = 0;
	end

	endcase
end

always @(*) begin
	case (fd_type)
	IMG_ARCHIE:    sd_lba = {(16'd0 + (fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 5'd0 : fd_spt) + sector[5:0], s_odd };
	IMG_ST:        sd_lba = ((fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 6'd0 : fd_spt) + sector[5:0] - 1'd1;
	IMG_PLUSD_IMG: sd_lba = (floppy_side ? 16'd0 : 16'd800) + fd_spt*track[6:0] + sector[5:0] - 1'd1;
	IMG_BBC:       sd_lba = (((fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 5'd0 : fd_spt) + sector[5:0]) >> 1;
	IMG_TI99:      sd_lba = (fd_spt*(floppy_side ? track[5:0] : 79-track[5:0]) + sector[5:0]) >> 1;
	IMG_BETA:      sd_lba = (((fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 5'd0 : fd_spt) + sector[5:0] - 1'd1) >> 1;
	default:       sd_lba = 0;
	endcase
end

always @(posedge clkcpu) begin
	integer i;

	for(i = 0; i < FD_NUM; i = i+1'd1) begin
		if (img_mounted[i]) begin
			fdn_present[i] <= |img_size;
			fdn_sector_size_code[i] <= image_sector_size_code;
			fdn_spt[i] <= image_spt;
			fdn_gap_len[i] <= image_gap_len;
			fdn_doubleside[i] <= image_doubleside;
			fdn_hd[i] <= image_hd;
			fdn_ed[i] <= image_ed;
			fdn_fm[i] <= image_fm;
			fdn_sector_base[i] <= image_sector_base;
			fdn_type[i] <= img_type;
		end
	end
end

// -------------------------------------------------------------------------
// ---------------------------- IRQ/DRQ handling ---------------------------
// -------------------------------------------------------------------------
reg cpu_selD;
reg cpu_rwD;
always @(posedge clkcpu) begin
	cpu_rwD <= cpu_sel & ~cpu_rw;
	cpu_selD <= cpu_sel;
end

wire cpu_we = cpu_sel & ~cpu_rw & ~cpu_rwD;

reg irq_set;

// floppy_reset and read of status register/write of command register clears irq
reg cpu_rw_cmdstatus;
always @(posedge clkcpu)
  cpu_rw_cmdstatus <= ~cpu_selD && cpu_sel && cpu_addr == FDC_REG_CMDSTATUS;

wire irq_clr = !floppy_reset || cpu_rw_cmdstatus;

always @(posedge clkcpu) begin
	if(irq_clr) irq <= 1'b0;
	else if(irq_set) irq <= 1'b1;
end

reg drq_set;

reg cpu_rw_data;
always @(posedge clkcpu)
	cpu_rw_data <= ~cpu_selD && cpu_sel && cpu_addr == FDC_REG_DATA;

wire drq_clr = !floppy_reset || cpu_rw_data;

always @(posedge clkcpu) begin
	if(drq_clr) drq <= 1'b0;
	else if(drq_set) drq <= 1'b1;
end

// -------------------------------------------------------------------------
// ----------------------------- floppy demux ------------------------------
// -------------------------------------------------------------------------

reg [WIDX:0] fdn;
always begin
	integer i;
	
	fdn = 0;
	for(i = FD_NUM-1; i >= 0; i = i - 1) if(!floppy_drive[i]) fdn = i[WIDX:0];
end

wire        fd_any         = ~&floppy_drive;

wire        fd_index       = fd_any ? fdn_index[fdn]       : 1'b0;
wire        fd_ready       = fd_any ? fdn_ready[fdn]       : 1'b0;
wire  [6:0] fd_track       = fd_any ? fdn_track[fdn]       : 7'd0;
wire  [5:0] fd_sector      = fd_any ? fdn_sector[fdn]      : 5'd0;
wire        fd_sector_hdr  = fd_any ? fdn_sector_hdr[fdn]  : 1'b0;
wire        fd_sector_data = fd_any ? fdn_sector_data[fdn] : 1'b0;
wire        fd_dclk_en     = fd_any ? fdn_dclk[fdn]        : 1'b0;
wire        fd_present     = fd_any ? fdn_present[fdn]     : 1'b0;
wire        fd_writeprot   = fd_any ? img_wp[fdn]          : 1'b1;

wire        fd_doubleside  = fdn_doubleside[fdn];
wire  [5:0] fd_spt         = fdn_spt[fdn];
wire  [1:0] fd_sector_size_code = fdn_sector_size_code[fdn];
wire [10:0] fd_sector_size = 11'd128 << fdn_sector_size_code[fdn];
wire        fd_sector_base = fdn_sector_base[fdn];
wire  [2:0] fd_type        = fdn_type[fdn];

assign floppy_ready = fd_ready && fd_present;

// -------------------------------------------------------------------------
// -------------------- virtual floppy drive mechanics ---------------------
// -------------------------------------------------------------------------

wire       fdn_index[FD_NUM];
wire       fdn_ready[FD_NUM];
wire [6:0] fdn_track[FD_NUM];
wire [5:0] fdn_sector[FD_NUM];
wire       fdn_sector_hdr[FD_NUM];
wire       fdn_sector_data[FD_NUM];
wire       fdn_dclk[FD_NUM];

wire fd_motor;
reg step_in, step_out;

generate
	genvar i;
	
	for(i=0; i < FD_NUM; i = i+1) begin :fdd

		floppy #(.CLK_EN(CLK_EN)) floppy
		(
			.clk         ( clkcpu             ),
			.clk8m_en    ( clk8m_en           ),

			// control signals into floppy
			.select      ( fd_any && fdn == i ),
			.motor_on    ( fd_motor           ),
			.step_in     ( step_in            ),
			.step_out    ( step_out           ),

			// physical parameters
			.inserted    ( fdn_present[i]     ),
			.sector_size_code ( fdn_sector_size_code[i]  ),
			.spt         ( fdn_spt[i]         ),
			.sector_gap_len ( fdn_gap_len[i]  ),
			.sector_base ( fdn_sector_base[i] ),
			.hd          ( fdn_hd[i]          ),
			.ed          ( fdn_ed[i]          ),
			.fm          ( fdn_fm[i]          ),

			// status signals generated by floppy
			.dclk_en     ( fdn_dclk[i]        ),
			.track       ( fdn_track[i]       ),
			.sector      ( fdn_sector[i]      ),
			.sector_hdr  ( fdn_sector_hdr[i]  ),
			.sector_data ( fdn_sector_data[i] ),
			.ready       ( fdn_ready[i]       ),
			.index       ( fdn_index[i]       )
		);
	end
endgenerate


// -------------------------------------------------------------------------
// ----------------------- internal state machines -------------------------
// -------------------------------------------------------------------------

// --------------------------- Motor handling ------------------------------

// if motor is off and type 1 command with "spin up sequnce" bit 3 set
// is received then the command is executed after the motor has
// reached full speed for 5 rotations (800ms spin-up time + 5*200ms =
// 1.8sec) If the floppy is idle for 10 rotations (2 sec) then the
// motor is switched off again
localparam MOTOR_IDLE_COUNTER = 4'd10;
reg [3:0] motor_timeout_index /* verilator public */;
reg indexD;
reg busy /* verilator public */;
reg [3:0] motor_spin_up_sequence /* verilator public */;

assign fd_motor = EXT_MOTOR ? floppy_motor : motor_on;

// consider spin up done either if the motor is not supposed to spin at all or
// if it's supposed to run and has left the spin up sequence
wire motor_spin_up_done = (!motor_on) || (motor_on && (motor_spin_up_sequence == 0));

// ---------------------------- step handling ------------------------------

localparam STEP_PULSE_LEN = 16'd1;
localparam STEP_PULSE_CLKS = STEP_PULSE_LEN * CLK_EN;
reg [15:0] step_pulse_cnt;

// the step rate is only valid for command type I
wire [19:0] step_rate_clk = 
           (cmd[1:0]==2'b00)               ? (16'd6 *CLK_EN-1'd1):   //  6ms
           (cmd[1:0]==2'b01)               ? (16'd12*CLK_EN-1'd1):   // 12ms
           (MODEL == 2 && cmd[1:0]==2'b10) ? (16'd2 *CLK_EN-1'd1):   //  2ms
           (cmd[1:0]==2'b10)               ? (16'd20*CLK_EN-1'd1):   // 20ms
           (MODEL == 2)                    ? (16'd3 *CLK_EN-1'd1):   //  3ms
                                             (16'd30*CLK_EN-1'd1);   // 30ms

reg [19:0] step_rate_cnt;
reg [23:0] delay_cnt;

assign floppy_step = step_in | step_out;

// flag indicating that a "step" is in progress
wire step_busy = (step_rate_cnt != 0);
wire delaying = (delay_cnt != 0);

wire fd_track0 = (fd_track == 0);

reg [7:0] step_to;
reg RNF;
reg sector_inc_strobe;
reg track_inc_strobe;
reg track_dec_strobe;
reg track_clear_strobe;

always @(posedge clkcpu) begin
	reg [1:0] seek_state;
	reg notready_wait;
	reg sector_not_found;
	reg irq_at_index;
	reg [1:0] data_transfer_state;
        reg fd_sector_hdrD;   

	sector_inc_strobe <= 1'b0;
	track_inc_strobe <= 1'b0;
	track_dec_strobe <= 1'b0;
	track_clear_strobe <= 1'b0;
	irq_set <= 1'b0;

	if(!floppy_reset) begin
		motor_on <= 1'b0;
		busy <= 1'b0;
		step_in <= 1'b0;
		step_out <= 1'b0;
		sd_card_read <= 0;
		sd_card_write <= 0;
		data_transfer_start <= 1'b0;
		seek_state <= 0;
		notready_wait <= 1'b0;
		sector_not_found <= 1'b0;
		irq_at_index <= 1'b0;
		data_transfer_state <= 2'b00;
		RNF <= 1'b0;
	        fd_sector_hdrD <= 1'b0;   
	end else if (clk8m_en) begin
		sd_card_read <= 0;
		sd_card_write <= 0;
		data_transfer_start <= 1'b0;
	        fd_sector_hdrD <= fd_sector_hdr;   

		// disable step signal after 1 msec
		if(step_pulse_cnt != 0) 
			step_pulse_cnt <= step_pulse_cnt - 16'd1;
		else begin
			step_in <= 1'b0;
			step_out <= 1'b0;
		end

		 // step rate timer
		if(step_rate_cnt != 0) 
			step_rate_cnt <= step_rate_cnt - 16'd1;

		// delay timer
		if(delay_cnt != 0) 
			delay_cnt <= delay_cnt - 1'd1;

		// just received a new command
		if(cmd_rx) begin
			busy <= 1'b1;
			notready_wait <= 1'b0;
			sector_not_found <= 1'b0;
			data_transfer_state <= 2'b00;

			if(cmd_type_1 || cmd_type_2 || cmd_type_3) begin
				RNF <= 1'b0;
				motor_on <= 1'b1;
				// 'h' flag '0' -> wait for spin up
				if (!motor_on && !cmd[3]) motor_spin_up_sequence <= 6;   // wait for 6 full rotations
			end

			// handle "forced interrupt"
			if(cmd_type_4) begin
				busy <= 1'b0;
				if(cmd[3]) irq_set <= 1'b1;
				if(cmd[3:2] == 2'b01) irq_at_index <= 1'b1;
				// From Hatari: Starting a Force Int command when idle should set the motor bit and clear the spinup bit (verified on STF)
				if (!busy) motor_on <= 1'b1;
			end
		end

		// execute command if motor is not supposed to be running or
		// wait for motor spinup to finish
		if(busy && motor_spin_up_done && !step_busy && !delaying) begin

			// ------------------------ TYPE I -------------------------
			if(cmd_type_1) begin
				if(!fd_present) begin
					// no image selected -> send irq after 6 ms
					if (!notready_wait) begin
						delay_cnt <= 16'd6*CLK_EN;
						notready_wait <= 1'b1;
					end else begin
						RNF <= 1'b1;
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end
				end else
				// evaluate command
				case (seek_state)
				0: begin
					// restore
					if(cmd[7:4] == 4'b0000) begin
						if (fd_track0) begin
							track_clear_strobe <= 1'b1;
							seek_state <= 2;
						end else begin
							step_dir <= 1'b1;
							seek_state <= 1;
						end
					end

					// seek
					if(cmd[7:4] == 4'b0001) begin
						if (track == step_to) seek_state <= 2;
						else begin
							step_dir <= (step_to < track);
							seek_state <= 1;
						end
					end

					// step
					if(cmd[7:5] == 3'b001) seek_state <= 1;

					// step-in
					if(cmd[7:5] == 3'b010) begin
						step_dir <= 1'b0;
						seek_state <= 1;
					end

					// step-out
					if(cmd[7:5] == 3'b011) begin
						step_dir <= 1'b1;
						seek_state <= 1;
					end
				   end

				// do the step
				1: begin
					if (step_dir)
						step_in <= 1'b1;
					else
						step_out <= 1'b1;

					// update the track register if seek/restore or the update flag set
					if( (!cmd[6] && !cmd[5]) || ((cmd[6] || cmd[5]) && cmd[4]))
						if (step_dir)
							track_dec_strobe <= 1'b1;
						else
							track_inc_strobe <= 1'b1;

					step_pulse_cnt <= STEP_PULSE_CLKS - 1'd1;
					step_rate_cnt <= step_rate_clk;

					seek_state <= (!cmd[6] && !cmd[5]) ? 0 : 2; // loop for seek/restore
				   end

				// verify
				2: begin
					if (cmd[2]) begin
						delay_cnt <= 16'd3*CLK_EN; // TODO: implement verify, now just delay one more step
					end
					seek_state <= 3;
				   end

				// finish
				3: begin
					busy <= 1'b0;
					irq_set <= 1'b1; // emit irq when command done
					seek_state <= 0;
				   end
				endcase
			end // if (cmd_type_1)

			// ------------------------ TYPE II -------------------------
			if(cmd_type_2) begin
				if(!fd_present) begin
					// no image selected -> send irq after 6 ms
					if (!notready_wait) begin
						delay_cnt <= 16'd6*CLK_EN;
						notready_wait <= 1'b1;
					end else begin
						RNF <= 1'b1;
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end
				end else if (sector_not_found) begin
					busy <= 1'b0;
					irq_set <= 1'b1; // emit irq when command done
					RNF <= 1'b1;
				end else if (cmd[2] && !notready_wait) begin
					// e flag: 15 ms settling delay
					delay_cnt <= 16'd15*CLK_EN;
					notready_wait <= 1'b1;
					// read sector
				end else begin
					if(cmd[7:5] == 3'b100) begin
						if ((sector - fd_sector_base) >= fd_spt) begin
							// wait 5 rotations (1 sec) before setting RNF
							sector_not_found <= 1'b1;
							delay_cnt <= 24'd1000 * CLK_EN;
						end else if (sd_state == SD_IDLE) begin
							case (data_transfer_state)

							2'b00: if (fifo_cpuptr == 0) begin
								// SD Card phase
								sd_card_read <= 1;
								data_transfer_state <= 2'b01;
							end

							2'b01: begin
								// CPU phase
								// we are busy until the right sector header passes under 
								// the head and the sd-card controller indicates the sector
								// is in the fifo
								if(fd_ready && fd_sector_hdrD && !fd_sector_hdr && (fd_sector == sector)) data_transfer_start <= 1'b1;

								if(data_transfer_done) begin
									data_transfer_state <= 2'b00;
									if (cmd[4]) sector_inc_strobe <= 1'b1; // multiple sector transfer
									else begin
										busy <= 1'b0;
										irq_set <= 1'b1; // emit irq when command done
									end
								end
							end

							default :;
							endcase

						end
					end

					// write sector
					if(cmd[7:5] == 3'b101) begin
                        if (fd_writeprot) begin
                            // on write protection immediately end command
                            busy <= 1'b0;
                            irq_set <= 1'b1;
                        end else begin

                            if ((sector - fd_sector_base) >= fd_spt) begin
                                // wait 5 rotations (1 sec) before setting RNF
                                sector_not_found <= 1'b1;
                                delay_cnt <= 24'd1000 * CLK_EN;
                            end else if (sd_state == SD_IDLE) begin
                                case (data_transfer_state)
                                2'b00: begin
                                    // pre-read phase
                                        if (fd_sector_size_code < 2) sd_card_read <= 1;
                                        data_transfer_state <= 2'b10;
                                    end
                                2'b10: begin
                                    // CPU phase
                                    if (fifo_cpuptr == 0 && fd_ready && fd_sector_hdrD && !fd_sector_hdr && (fd_sector == sector)) data_transfer_start <= 1'b1;
                                    if (data_transfer_done) begin
                                        sd_card_write <= 1;
                                        data_transfer_state <= 2'b11;
                                    end
                                end

                                2'b11: begin
                                    // SD Card phase
                                    data_transfer_state <= 2'b00;
                                    if (cmd[4]) sector_inc_strobe <= 1'b1; // multiple sector transfer
                                    else begin
                                        busy <= 1'b0;
                                        irq_set <= 1'b1; // emit irq when command done
                                    end
                                end

                                default: ;
                                endcase
                            end
						end
					end
				end
			end

			// ------------------------ TYPE III -------------------------
			if(cmd_type_3) begin
				if(!fd_present) begin
					// no image selected -> send irq immediately
					RNF <= 1'b1;
					busy <= 1'b0; 
					irq_set <= 1'b1; // emit irq when command done
				end else begin
					// read track TODO: fake
					if(cmd[7:4] == 4'b1110) begin
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end

					// write track TODO: fake
					if(cmd[7:4] == 4'b1111) begin
						busy <= 1'b0;
						irq_set <= 1'b1; // emit irq when command done
					end

					// read address
					if(cmd[7:4] == 4'b1100) begin
						// we are busy until the next setor header arrives under the head
						if(fd_ready && !fd_sector_hdrD && fd_sector_hdr)
							data_transfer_start <= 1'b1;

						if(data_transfer_done) begin
							busy <= 1'b0;
							irq_set <= 1'b1; // emit irq when command done
						end
					end
				end
			end
		end

		// stop motor if there was no command for 10 index pulses
		indexD <= fd_index;
		if(indexD && !fd_index) begin
			irq_at_index <= 1'b0;
			if (irq_at_index) irq_set <= 1'b1;

			// let motor timeout run once fdc is not busy anymore
			if(!busy && motor_spin_up_done) begin
				if(motor_timeout_index != 0)
					motor_timeout_index <= motor_timeout_index - 4'd1;
				else if(motor_on)
					motor_timeout_index <= MOTOR_IDLE_COUNTER;

				if(motor_timeout_index == 1)
					motor_on <= 1'b0;
			end

			if(motor_spin_up_sequence != 0)
				motor_spin_up_sequence <= motor_spin_up_sequence - 4'd1;
		end
		if(busy) motor_timeout_index <= 0;
	end
end

// floppy delivers data at a floppy generated rate (usually 250kbit/s), so the start and stop
// signals need to be passed forth and back from cpu clock domain to floppy data clock domain
reg data_transfer_start;
reg data_transfer_done;

// ==================================== FIFO ==================================

// 0.5/1 kB buffer used to receive a sector as fast as possible from from the io
// controller. The internal transfer afterwards then runs at 250000 Bit/s
reg  [10:0] fifo_cpuptr;
reg  [9:0] fifo_cpuptr_adj;
wire [7:0] fifo_q;
reg        s_odd; //odd sector
reg  [9:0] fifo_sdptr;

always @(*) begin
	if (fd_sector_size_code == 3)
		fifo_sdptr = { s_odd, sd_buff_addr };
	else
		fifo_sdptr = { 1'b0, sd_buff_addr };

	if (fd_sector_size_code == 1)
		fifo_cpuptr_adj = { 1'b0, (fd_spt[0] & (track[0] ^ !floppy_side)) ^ sector[0] ^ fd_sector_base, fifo_cpuptr[7:0] };
	else
		fifo_cpuptr_adj = fifo_cpuptr[9:0];
end

reg data_in_strobe;
reg [7:0] data_in;

`ifdef VERILATOR
fdc1772_dpram #(8, 10) fifo
(
	.clock(clkcpu),

	.address_a(fifo_sdptr),
	.data_a(sd_dout),
	.wren_a(sd_dout_strobe & sd_ack),
	.q_a(sd_din),

	.address_b(fifo_cpuptr_adj),
	.data_b(data_in),
	.wren_b(data_in_strobe),
	.q_b(fifo_q)
);
`else
fdc_dpram fifo
(
    .clka(clkcpu),
    .reseta(1'b0),
    .cea(1'b1),
    .ada(fifo_sdptr),
    .wrea(sd_dout_strobe & sd_ack),
    .dina(sd_dout),
    .ocea(1'b1),
    .douta(sd_din),

    .clkb(clkcpu),
    .resetb(1'b0),
    .ceb(1'b1),
    .adb(fifo_cpuptr_adj),
    .wreb(data_in_strobe),
    .dinb(data_in),
    .oceb(1'b1),
    .doutb(fifo_q)
);
`endif

// ------------------ SD card control ------------------------
localparam SD_IDLE = 0;
localparam SD_READ_WAIT = 1;
localparam SD_WRITE_WAIT = 2;
localparam SD_READ = 3;
localparam SD_WRITE = 4;

reg [2:0] sd_state;
reg       sd_card_write;
reg       sd_card_read;

always @(posedge clkcpu) begin
	reg sd_ackD;
	reg sd_card_readD;
	reg sd_card_writeD;

	sd_card_readD <= sd_card_read;
	sd_card_writeD <= sd_card_write;
	sd_ackD <= sd_ack;
	if (sd_ack) {sd_rd, sd_wr} <= 0;

	case (sd_state)
	SD_IDLE:
	begin
		s_odd <= 1'b0;
		if (~sd_card_readD & sd_card_read)
			sd_state <= SD_READ_WAIT;
		else if (~sd_card_writeD & sd_card_write)
			sd_state <= SD_WRITE_WAIT;
	end

	SD_READ_WAIT:
        begin
	   // request only if card is not busy otherwise
	   if(!sd_ack) begin
	      sd_rd[fdn] <= 1;
	      sd_state <= SD_READ;
	   end
	end
	  
	SD_READ:
	if (sd_ackD & ~sd_ack) begin
		if (s_odd || fd_sector_size_code != 3) begin
			sd_state <= SD_IDLE;
		end else begin
			s_odd <= 1;
			sd_rd[fdn] <= 1;
		end
	end

	SD_WRITE_WAIT:
        begin
	   // request only if card is not busy otherwise
	   if(!sd_ack) begin
	      sd_wr[fdn] <= 1;
	      sd_state <= SD_WRITE;
	   end
	end
	  
	SD_WRITE:
	if (sd_ackD & ~sd_ack) begin
		if (s_odd || fd_sector_size_code != 3) begin
			sd_state <= SD_IDLE;
		end else begin
			s_odd <= 1;
			sd_wr[fdn] <= 1;
		end
	end

	default: ;
	endcase
end

// -------------------- CPU data read/write -----------------------
reg data_in_valid;

function [15:0] crc;
	input [15:0] curcrc;
	input  [7:0] val;
	reg    [3:0] i;
	begin
		crc = {curcrc[15:8] ^ val, 8'h00};
		for (i = 0; i < 8; i=i+1'd1) begin
			if(crc[15]) begin
				crc = crc << 1;
				crc = crc ^ 16'h1021;
			end
			else crc = crc << 1;
		end
		crc = {curcrc[7:0] ^ crc[15:8], crc[7:0]};
	end
endfunction

always @(posedge clkcpu) begin
	reg        data_transfer_startD;
	reg [10:0] data_transfer_cnt;
	reg [15:0] crcval;
	reg        crc_en;

	crc_en <= 0;
	if(crc_en) crcval <= crc(crcval, data_out);

	if (cpu_we && cpu_addr == FDC_REG_DATA) begin
		data_out <= data_in;
		data_in_valid <= 1;
	end

	// reset fifo read pointer on reception of a new command or 
	// when multi-sector transfer increments the sector number
	if(cmd_rx || sector_inc_strobe) begin
		data_in_valid <= 0;
		data_transfer_cnt <= 0;
		fifo_cpuptr <= 0;
	end

	drq_set <= 1'b0;
	if (clk8m_en) data_transfer_done <= 0;
	data_transfer_startD <= data_transfer_start;
	// received request to read data
	if(~data_transfer_startD & data_transfer_start) begin

		// read_address command has 6 data bytes
		if(cmd[7:4] == 4'b1100) begin
			crcval <= 16'hB230;
			data_transfer_cnt <= 11'd6+11'd1;
		end

		// read/write sector has SECTOR_SIZE data bytes
		if(cmd[7:6] == 2'b10)
			data_transfer_cnt <= fd_sector_size + 1'd1;

		// write sector asserts drq earlier to fill up the data register in time
		if(cmd[7:5] == 3'b101) drq_set <= !data_in_valid;
	end

	// advance fifo pointer when the write sector data consumed
	data_in_strobe <= 1'b0;
	if(cmd[7:5] == 3'b101 && data_in_strobe) fifo_cpuptr <= fifo_cpuptr + 1'd1;

	if(fd_dclk_en) begin
		if(data_transfer_cnt != 0) begin
			if(data_transfer_cnt != 1) begin
				data_lost <= 1'b0;
				if (drq) data_lost <= 1'b1;
				// raise drq, except when the last byte is already taken from the CPU for write
				if (cmd[7:5] != 3'b101 || data_transfer_cnt != 2) drq_set <= 1'b1;

				// read_address
				if(cmd[7:4] == 4'b1100) begin
					case(data_transfer_cnt)
						7: begin data_out <= fd_track; crc_en <= 1; end
						6: begin data_out <= { 7'b0000000, (INVERT_HEAD_RA != 0) ^ floppy_side }; crc_en <= 1; end
						5: begin data_out <= fd_sector; crc_en <= 1; end
						4: begin data_out <= fd_sector_size_code[1:0]; crc_en <= 1; end // TODO: sec size 0=128, 1=256, 2=512, 3=1024
						3: data_out <= crcval[15:8];
						2: data_out <= crcval[7:0];
					endcase // case (data_read_cnt)
				end

				// read sector
				if(cmd[7:5] == 3'b100 && fifo_cpuptr != fd_sector_size) begin
					data_out <= fifo_q;
					fifo_cpuptr <= fifo_cpuptr + 1'd1;
				end
				// write sector
				if(cmd[7:5] == 3'b101 && fifo_cpuptr != fd_sector_size) begin
					data_in_strobe <= 1;
					data_in_valid <= 0;
				end

			end

			// count down and stop after last byte
			data_transfer_cnt <= data_transfer_cnt - 11'd1;
			if(data_transfer_cnt == 1)
				data_transfer_done <= 1'b1;
		end
	end
end

// the status byte
wire [7:0] status = { (MODEL == 1 || MODEL == 3) ? !floppy_ready : motor_on,
		      (cmd[7:5] == 3'b101 || cmd[7:4] == 4'b1111 || cmd_type_1) && fd_writeprot, // wrprot (only for write!)
		      cmd_type_1?motor_spin_up_done:1'b0,  // data mark
		      RNF,                                 // seek error/record not found
		      1'b0,                                // crc error
		      (cmd_type_1 | cmd_type_4)?fd_track0:data_lost, // track0/data lost
		      (cmd_type_1 | cmd_type_4)?~fd_index:drq,       // index mark/drq
		      busy } /* synthesis keep */;

reg [7:0] track /* verilator public */;
reg [7:0] sector;
reg [7:0] data_out;

reg step_dir;
reg motor_on /* verilator public */ = 1'b0;
reg data_lost;

// ---------------------------- command register -----------------------   
reg [7:0] cmd /* verilator public */;
wire cmd_type_1 = (cmd[7] == 1'b0);
wire cmd_type_2 = (cmd[7:6] == 2'b10);
wire cmd_type_3 = (cmd[7:5] == 3'b111) || (cmd[7:4] == 4'b1100);
wire cmd_type_4 = (cmd[7:4] == 4'b1101);

localparam FDC_REG_CMDSTATUS    = 0;
localparam FDC_REG_TRACK        = 1;
localparam FDC_REG_SECTOR       = 2;
localparam FDC_REG_DATA         = 3;

// CPU register read
always @(*) begin
	cpu_dout = 8'h00;

	if(cpu_sel && cpu_rw) begin
		case(cpu_addr)
			FDC_REG_CMDSTATUS: cpu_dout = status;
			FDC_REG_TRACK:     cpu_dout = track;
			FDC_REG_SECTOR:    cpu_dout = sector;
			FDC_REG_DATA:      cpu_dout = data_out;
		endcase
	end
end

// cpu register write
reg cmd_rx /* verilator public */;
reg cmd_rx_i;

always @(posedge clkcpu) begin
	if(!floppy_reset) begin
		// clear internal registers
		cmd <= 8'h00;
		track <= 8'h00;
		sector <= 8'h00;

		// reset state machines and counters
		cmd_rx_i <= 1'b0;
		cmd_rx <= 1'b0;
	end else begin

		// cmd_rx is delayed to make sure all signals (the cmd!) are stable when
		// cmd_rx is evaluated
		cmd_rx <= cmd_rx_i;

		// command reception is ack'd by fdc going busy
		if((!cmd_type_4 && busy) || (clk8m_en && cmd_type_4 && !busy)) cmd_rx_i <= 1'b0;

		// only react if stb just raised
		if(cpu_we) begin
			if(cpu_addr == FDC_REG_CMDSTATUS) begin       // command register
				cmd <= cpu_din;
				cmd_rx_i <= 1'b1;
				// ------------- TYPE I commands -------------
				if(cpu_din[7:4] == 4'b0000) begin               // RESTORE
					step_to <= 8'd0;
					track <= 8'hff;
				end

				if(cpu_din[7:4] == 4'b0001) begin               // SEEK
					step_to <= data_in;
				end

				if(cpu_din[7:5] == 3'b001) begin                // STEP
				end

				if(cpu_din[7:5] == 3'b010) begin                // STEP-IN
				end

				if(cpu_din[7:5] == 3'b011) begin                // STEP-OUT
				end

				// ------------- TYPE II commands -------------
				if(cpu_din[7:5] == 3'b100) begin                // read sector
				end

				if(cpu_din[7:5] == 3'b101) begin                // write sector
				end

				// ------------- TYPE III commands ------------
				if(cpu_din[7:4] == 4'b1100) begin               // read address
				end

				if(cpu_din[7:4] == 4'b1110) begin               // read track
				end

				if(cpu_din[7:4] == 4'b1111) begin               // write track
				end

				// ------------- TYPE IV commands -------------
				if(cpu_din[7:4] == 4'b1101) begin               // force intrerupt
				end
			end

			if(cpu_addr == FDC_REG_TRACK)                    // track register
				track <= cpu_din;

			if(cpu_addr == FDC_REG_SECTOR)                   // sector register
				sector <= cpu_din;

			if(cpu_addr == FDC_REG_DATA) begin               // data register
				data_in <= cpu_din;
			end
		end

		if (sector_inc_strobe) sector <= sector + 1'd1;
		if (track_inc_strobe) track <= track + 1'd1;
		if (track_dec_strobe) track <= track - 1'd1;
		if (track_clear_strobe) track <= 8'd0;
	end
end

endmodule

`ifdef VERILATOR
module fdc1772_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=9)
(
	input                   clock,

	input   [ADDRWIDTH-1:0] address_a,
	input   [DATAWIDTH-1:0] data_a,
	input                   wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input   [ADDRWIDTH-1:0] address_b,
	input   [DATAWIDTH-1:0] data_b,
	input                   wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always @(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always @(posedge clock) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end

endmodule
`endif
