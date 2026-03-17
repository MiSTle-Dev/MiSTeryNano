module MCU_BIROM
  (
   input 	CLK,
   input 	EN,
   input [11:0] AD,
   output reg [7:0] DO
   );
   
   reg [7:0] 	rom[0:4095];
   initial begin
`ifdef VERILATOR
      $readmemh ("../src/ikbd/rom/ikbd.hex", rom, 0);
`else
      $readmemh ("ikbd.hex", rom, 0);
`endif
   end
   
   always @(posedge CLK) begin
      if ( EN )
	DO <= rom[AD];
   end
   
endmodule // MCU_BIROM
