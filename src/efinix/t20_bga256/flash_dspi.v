//
// flash_dspi.v - reading Winbond W25Q32, 32MBit spi flash
// jedec id ef4016
//
// pullups and H1 pins on t20bga256 dev board
// DI   -> R32 / 4 / GPIOL_08
// CS   -> R1  / 8 / GPIOL_00
// WP   -> R2  / -
// DO   -> R33 / 6 / GPIOL_09
// HOLD -> R3  / -
// CLK  -> -   / 2 / GPIOL_01

//
// This module runs a SPI flash in DSPI/IO mode. In this mode the
// flash uses 2 bit IO for address and data. A full random 16 bit
// read cycle takes 32 clocks in this mode. Furthermore the
// “Continuous Read Mode” is being enabled in the first read which
// allows one 16 bit read in 24 cycles.
//
// At 80MHz this results in a random access time of 300 ns. At
// 100 Mhz, it would be 240ns and at the max allowed 104MHz it
// would be 230ns

module flash
(
 input		   clk,
 input		   resetn,
 output		   ready, 

 // chipset read interface
 input [21:0]	   address, // 16 bit word address
 input		   cs, 
 output reg [15:0] dout,
 
 // interface to the chip
 output reg	   mspi_cs,
 inout		   mspi_di, // data in into flash chip
 inout		   mspi_do, // data out from flash chip
 output        mspi_wp,
 output        mspi_hold,
 
`ifdef VERILATOR		
 input [1:0]	   mspi_din, 
`endif
 
 output reg	   busy
);

reg		   dspi_mode;

wire [1:0]	   dspi_out;
   
wire [1:0] output_en = { 
    dspi_mode?(state<=6'd22):1'b0,    // io1 is do in SPI mode and thus never driven
    dspi_mode?(state<=6'd22):1'b1     // io0 is di in SPI mode and thus always driven
};
      
wire [1:0] data_out = {
    dspi_mode?dspi_out[1]:1'b1,      // never driven in SPI mode
    dspi_mode?dspi_out[0]:spi_di       
};

assign mspi_do   = output_en[1]?data_out[1]:1'bz;
assign mspi_di   = output_en[0]?data_out[0]:1'bz;
   
wire [7:0] CMD_RD_DIO = 8'hbb; // "fast read dual IO" command
wire [7:0] CMD_RDP    = 8'hab; // "release from deep powerdown"

// M(7:4) = 1010 -> “Continuous Read Mode”
wire [7:0] M = 8'b1010_0000;
     
reg [5:0] state;
reg [7:0] init;

// flash is ready when init phase has ended
assign ready = (init == 8'd0);  

localparam RDP_START       = 128;  // start must be multiple of 8
localparam DSPI_EXIT_START = 192;
   
// send 16 1's during init on IO0 to make sure M4 = 1 and dspi is left
wire spi_di =
     ((init>=RDP_START-8) && (init<RDP_START))?CMD_RDP[init[2:0]]:
     (init>1)?1'b1:
     CMD_RD_DIO[3'd7-state[2:0]];  // the command is sent in spi mode
   
assign dspi_out = 
		  (state== 6'd8)?{1'b0,address[21]}:
		  (state== 6'd9)?address[20:19]:
		  (state==6'd10)?address[18:17]:
		  (state==6'd11)?address[16:15]:
		  (state==6'd12)?address[14:13]:
		  (state==6'd13)?address[12:11]:
		  (state==6'd14)?address[10:9]:
		  (state==6'd15)?address[8:7]:
		  (state==6'd16)?address[6:5]:
		  (state==6'd17)?address[4:3]:
		  (state==6'd18)?address[2:1]:
		  (state==6'd19)?{address[0],1'b0}:
		  (state==6'd20)?M[7:6]:
		  (state==6'd21)?M[5:4]:
		  (state==6'd22)?M[3:2]:
		  (state==6'd23)?M[1:0]:
		  2'b00;   
   
`ifdef VERILATOR
wire [1:0] dspi_in = mspi_din;  
`else
wire [1:0] dspi_in = { mspi_do, mspi_di };  
`endif
   
always @(posedge clk or negedge resetn) begin
   reg csD, csD2;
   
   if(!resetn) begin
      // initially assume regular spi mode
      dspi_mode <= 1'b0;
      mspi_cs <= 1'b1;      
      busy <= 1'b0;
      init <= 8'd255;
      csD <= 1'b0;
      state <= 6'd0;
   end else begin
      csD <= cs;     // bring cs into local clock domain
      csD2 <= csD;   // delay to detect rising edge

      // send 16 1's on IO0 to make sure M4 = 1 and dspi is left and we are in a known state
      if(init != 5'd0) begin

	 // send 16 '1 bits
         if(init == DSPI_EXIT_START)    mspi_cs <= 1'b0;  // select flash chip at begin of 16 1's 
         if(init == DSPI_EXIT_START-16) mspi_cs <= 1'b1;  // de-select flash chip at end of 16 1's
	 
	 // send "release from deep powerdown" (RDP/0xab)
	 if(init == RDP_START)   mspi_cs <= 1'b0;
	 if(init == RDP_START-8) mspi_cs <= 1'b1;

         if(init != 8'd1 || !busy)
           init <= init - 8'd1;
      end
	 
      // wait for rising edge of cs or end of init phase
      if((csD && !csD2 && !busy)||(init == 8'd2)) begin
        mspi_cs <= 1'b0;	  // select flash chip	 
        busy <= 1'b1;

        // skip sending command if already in DSPI mode and M(5:4) == (1:0) sent
        if(dspi_mode) state <= 6'd8;
        else	      state <= 6'd0;
      end 

      // run state machine
      if(busy) begin
        state <= state + 6'd1;

        // enter dspi mode after command has been sent
        if(state == 6'd7)
            dspi_mode <= 1'b1;

        // latch output
        if(state == 6'd25) dout[15:14] <= dspi_in;
        if(state == 6'd26) dout[13:12] <= dspi_in;
        if(state == 6'd27) dout[11:10] <= dspi_in;
        if(state == 6'd28) dout[9:8]   <= dspi_in;
        if(state == 6'd29) dout[7:6]   <= dspi_in;
        if(state == 6'd30) dout[5:4]   <= dspi_in;
        if(state == 6'd31) dout[3:2]   <= dspi_in;
        if(state == 6'd32) dout[1:0]   <= dspi_in;

        // signal that the transfer is done
        if(state == 6'd32) begin
            state <= 6'd0;	    
            busy <= 1'b0;
            mspi_cs <= 1'b1;	// deselect flash chip	 
        end
      end
   end
end
   
endmodule
