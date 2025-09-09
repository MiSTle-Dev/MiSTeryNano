/*
    mcu_spi.v
 
    SPI version of MCU interface 
*/

module mcu_spi (
  input        clk,
  input        reset,

  // SPI interface to MCU
  input        spi_io_ss,
  input        spi_io_clk,
  input        spi_io_din,
  output reg   spi_io_dout,

  // byte interface to the various core components
  output reg      mcu_sys_strobe, // byte strobe for system control target  
  output reg      mcu_hid_strobe, // byte strobe for HID target  
  output reg      mcu_osd_strobe, // byte strobe for OSD target
  output reg      mcu_sdc_strobe, // byte strobe for SD card target
  output       mcu_start,
  input  [7:0] mcu_sys_din,
  input  [7:0] mcu_hid_din,
  input  [7:0] mcu_osd_din,
  input  [7:0] mcu_sdc_din,
  output [7:0] mcu_dout
);
   
// SPI runs in MODE1 
// -> idle state of data is low
// -> data is setup on rising clock edge
// -> data is read on falling clock edge

// bit/byte counter
reg [3:0] spi_cnt;

reg [7:0] spi_data_in;
reg [6:0] spi_sr_in;
reg spi_data_in_ready;

// read data on falling edge of spi clock
always @(negedge spi_io_clk or posedge spi_io_ss) begin
    if(spi_io_ss) begin
        spi_cnt <= 4'd0;
    end else begin
        // lower 3 bits cound bits, upper 8 bits count bytes
        spi_cnt <= spi_cnt + 4'd1;

        // shift bit in
        spi_sr_in <= { spi_sr_in[5:0], spi_io_din };

        // byte ready?
        if(spi_cnt[2:0] == 3'd7) begin
            // latch byte and raise ready flag
            spi_data_in <= { spi_sr_in, spi_io_din };
            spi_data_in_ready <= !spi_data_in_ready;
        end

        // Clear data ready at bit 3. If the reading side
        // runs at 32 Mhz, this will work up to 64 MHz
        // SPI clock. At higher clocks the word width must 
        // be increased.
//        if(spi_cnt[2:0] == 3'd3)
//            spi_data_in_ready <= 1'b0;
    end
end // always @ (negedge spi_io_clk or posedge spi_io_ss)
   
reg [7:0] spi_in_data;
assign mcu_start = spi_in_cnt == 2;  
assign mcu_dout = spi_in_data;
     
reg [7:0] spi_target;
reg [3:0] spi_in_cnt;

always @(posedge clk) begin
   reg [1:0] spi_data_in_readyD;

   spi_data_in_readyD <= { spi_data_in_readyD[0], spi_data_in_ready };

   mcu_sys_strobe <= 1'b0;   
   mcu_hid_strobe <= 1'b0;   
   mcu_osd_strobe <= 1'b0;   
   mcu_sdc_strobe <= 1'b0;   
   
   if(spi_io_ss)
      spi_in_cnt <= 4'd0;
   else begin
      // parse incoming bit whenever ready toggles
      // if(spi_data_in_readyD == 2'b01) begin
      if(spi_data_in_readyD[1] ^ spi_data_in_readyD[0]) begin
	 // incoming SPI byte is now in local clock domain

	 // first byte is target id. Else send external trigger
	 if(spi_in_cnt == 4'd0)
           spi_target <= spi_data_in;
	 else begin      
	    if(spi_target == 8'd0) mcu_sys_strobe <= 1'b1;
	    if(spi_target == 8'd1) mcu_hid_strobe <= 1'b1;
	    if(spi_target == 8'd2) mcu_osd_strobe <= 1'b1;
	    if(spi_target == 8'd3) mcu_sdc_strobe <= 1'b1;
   
            spi_in_data <= spi_data_in;
	 end
	 
	 if(spi_in_cnt != 4'd15)
           spi_in_cnt <= spi_in_cnt + 4'd1;
      end
   end
end

wire [7:0] in_byte = 
	   (spi_target == 8'd0)?mcu_sys_din:
	   (spi_target == 8'd1)?mcu_hid_din:
	   (spi_target == 8'd2)?mcu_osd_din:
	   (spi_target == 8'd3)?mcu_sdc_din:
	   8'h00;   
   
// setup data on rising edge of spi clock
always @(posedge spi_io_clk or posedge spi_io_ss) begin
    if(spi_io_ss) begin
        // ...
    end else begin
       spi_io_dout <= in_byte[~spi_cnt[2:0]];
    end
end

endmodule // osd_u8g2
