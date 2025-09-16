/*
    sysctrl.v
 
    generic system control interface from/via the MCU

    TODO: This is currently very core specific. This needs to be
    generic for all cores.
*/

module sysctrl (
  input		    clk,
  input		    reset,

  input		    data_in_strobe,
  input		    data_in_start,
  input [7:0]	    data_in,
  output reg [7:0]  data_out,

  // interrupt interface
  output	    int_out_n,
  input [7:0]	    int_in,
  output reg [7:0]  int_ack,

  input [1:0]	    buttons, // S0 and S1 buttons on Tang Nano 20k

  output reg [1:0]  leds, // two leds can be controlled from the MCU
  output reg [23:0] color, // a 24bit color to e.g. be used to drive the ws2812

  // IO port interface
  input	[31:0]	    port_status,         // status bits to report additional info about the port
  input	[7:0]	    port_out_available,  // number of bytes available for transmission to MCU
  output reg	    port_out_strobe,
  input [7:0]	    port_out_data,
  input	[7:0]	    port_in_available,   // number of unused bytes in the input buffer
  output reg	    port_in_strobe,
  output reg [7:0]  port_in_data,
		
  // values that can be configured by the user
  output reg [1:0]  system_chipset,
  output reg	    system_memory,
  output reg	    system_video,
  output reg [1:0]  system_reset,
  output reg [1:0]  system_scanlines,
  output reg [1:0]  system_volume,
  output reg	    system_wide_screen,
  output reg [1:0]  system_floppy_wprot,
  output reg	    system_cubase_en,
  output reg [1:0]  system_port_mouse,
  output reg [1:0]  system_port_joy,
  output reg	    system_tos_slot
);

reg [3:0] state;
reg [7:0] command;
reg [7:0] id;
   
// reverse data byte for rgb   
wire [7:0] data_in_rev = { data_in[0], data_in[1], data_in[2], data_in[3], 
                           data_in[4], data_in[5], data_in[6], data_in[7] };

// coldboot flash and system interrupt   
reg coldboot = 1'b1;   
reg sys_int = 1'b1;

// registers to report button interrupts
reg [1:0] buttonsD, buttonsD2;
reg	  buttons_irq_enable;
   
// the system cobtrol interrupt or any other interrupt (e,g sdc, hid, ...)
// activates the interrupt line to the MCU by pulling it low
assign int_out_n = (int_in != 8'h00 || sys_int)?1'b0:1'b1;
   
reg       port_out_availableD;
reg [7:0] port_cmd;   
reg [7:0] port_index;

// include the menu rom derived from atarist.xml
reg [11:0] menu_rom_addr;
reg [7:0]  menu_rom_data;

// generate hex e.g.:
// gzip -n atarist.xml
// xxd -c1 -p atarist.xml.gz > atarist_xml.hex
reg [7:0] atarist_xml[1024];
`ifndef EFINIX
   initial $readmemh("atarist_xml.hex", atarist_xml);
`else
  // it would be great if a global define could be used for the
  // filename here. But that does not work, at least not in efinity
  initial $readmemh("atarist_t20_xml.hex", atarist_xml);
`endif
   
always @(posedge clk)
  menu_rom_data <= atarist_xml[menu_rom_addr];
   
// process mouse events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;      
      leds <= 2'b00;        // after reset leds are off
      color <= 24'h000000;  // color black -> rgb led off

      buttons_irq_enable <= 1'b1;  // allow buttons irq
      int_ack <= 8'h00;
      coldboot = 1'b1;      // reset is actually the power-on-reset
      sys_int = 1'b1;       // coldboot interrupt

      port_out_strobe <= 1'b0;
      port_in_strobe <= 1'b0;
      
      // OSD value defaults. These should be sane defaults, but the MCU
      // will very likely override these early
      system_chipset <= 2'd0;       // regular ST
      system_memory <= 1'b0;        // 4 MB
      system_video <= 1'b0;         // color
      system_scanlines <= 2'b00;    // no scanlines
      system_volume <= 2'b00;       // mute
      system_wide_screen <= 1'b0;   // normal video 
      system_floppy_wprot <= 2'b00; // floppy not write protected
      system_cubase_en <= 1'b0;     // no cubase dongle
      system_port_mouse <= 2'b00;   // mouse on usb -> db9 joystick
      system_port_joy <= 1'b1;
      system_tos_slot <= 1'b0;      // primary tos slot
   end else begin // if (reset)
      //  bring button state into local clock domain
      buttonsD <= buttons;
      buttonsD2 <= buttonsD;
      
      int_ack <= 8'h00;
      port_out_strobe <= 1'b0;
      port_in_strobe <= 1'b0;

      // iack bit 0 acknowledges the system control interrupt
      if(int_ack[0]) sys_int <= 1'b0;      
            
      // (further) data has just become available, so raise interrupt
      port_out_availableD <= (port_out_available != 8'd0);
      if(port_out_available && !port_out_availableD)
	sys_int <= 1'b1;
      
      // monitor buttons for changes and raise interrupt
      if(buttons_irq_enable) begin
        if(buttonsD2 != buttonsD) begin
            // irq_enable prevents further interrupts until
            // the button state has actually been read by the MCU
            sys_int <= 1'b1;
            buttons_irq_enable <= 1'b0;
        end
      end

      if(data_in_strobe) begin
        if(data_in_start) begin
           state <= 4'd0;
           command <= data_in;
	   menu_rom_addr <= 12'd0;
	   data_out <= 8'h00;
        end else begin
            if(state != 4'd15) state <= state + 4'd1;
	    
            // CMD 0: status data
            if(command == 8'd0) begin
                // return some pattern that would not appear randomly
	        // on e.g. an unprogrammed device
                if(state == 4'd0) data_out <= 8'h5c;
                if(state == 4'd1) data_out <= 8'h42;
                if(state == 4'd2) data_out <= 8'h00;   // core id 0 = Generic core
            end
	   
            // CMD 1: there are two MCU controlled LEDs
            if(command == 8'd1) begin
                if(state == 4'd0) leds <= data_in[1:0];
            end

            // CMD 2: a 24 color value to be mapped e.g. onto the ws2812
            if(command == 8'd2) begin
                if(state == 4'd0) color[15: 8] <= data_in_rev;
                if(state == 4'd1) color[ 7: 0] <= data_in_rev;
                if(state == 4'd2) color[23:16] <= data_in_rev;
            end

            // CMD 3: return button state
            if(command == 8'd3) begin
               data_out <= { 6'b000000, buttons };
	       // re-enable interrupt once state has been read
               buttons_irq_enable <= 1'b1;
            end

            // CMD 4: config values (e.g. set by user via OSD)
            if(command == 8'd4) begin
                // second byte can be any character which identifies the variable to set 
                if(state == 4'd0) id <= data_in;

                if(state == 4'd1) begin
                    // Value "C": chipset ST(0), MegaST(1) or STE(2)
                    if(id == "C") system_chipset <= data_in[1:0];
                    // Value "M": 4MB(0) or 8MB(1)
                    if(id == "M") system_memory <= data_in[0];
                    // Value "V": color(0) or monochrome(1)
                    if(id == "V") system_video <= data_in[0];
                    // Value "R": coldboot(3), reset(1) or run(0)
                    if(id == "R") system_reset <= data_in[1:0];
                    // Value "S": scanlines none(0), 25%(1), 50%(2) or 75%(3)
                    if(id == "S") system_scanlines <= data_in[1:0];
                    // Value "A": volume mute(0), 33%(1), 66%(2) or 100%(3)
                    if(id == "A") system_volume <= data_in[1:0];
                    // Value "W": normal 4:3 screen (0), wide 16:9 screen (1)
                    if(id == "W") system_wide_screen <= data_in[0];
                    // Value "P": floppy write protecion None(0), A(1), B(2) both(3)
                    if(id == "P") system_floppy_wprot <= data_in[1:0];
                    // Value "Q": enable (1) or disable (0) Cubase dongle(s)
                    if(id == "Q") system_cubase_en <= data_in[0];
                    // Value "J": USB Mouse(0), DB9/Atari ST(1) or DB9/Amiga(2)
                    if(id == "J") system_port_mouse <= data_in[1:0];
                    // Value "U": USB Joy, Port0/Port1 or Port1/Port0 mapping order
                    if(id == "U") system_port_joy <= data_in[0];
                    // Value "T": Primary(0) TOS slot or Secondary(1)
                    if(id == "T") system_tos_slot <= data_in[0];
                end
            end

            // CMD 5: interrupt control
            if(command == 8'd5) begin
                // second byte acknowleges the interrupts
                if(state == 4'd0) int_ack <= data_in;

	        // interrupt[0] notifies the MCU of a FPGA cold boot e.g. if
                // the FPGA has been loaded via USB
                data_out <= { int_in[7:1], sys_int };
            end
	   
            // CMD 6: read system interrupt source
            if(command == 8'd6) begin
	        // bit[0]: coldboot flag
	        // bit[1]: port data is available
	        // bit[2]: buttons state change has been detected
                data_out <= { 5'b00000, !buttons_irq_enable, (port_out_available != 8'd0), coldboot };
	        // reading the interrupt source acknowledges the coldboot notification
	        if(state == 4'd0) coldboot <= 1'b0;            
	    end

            // CMD 7: port command (e.g. rs232)
            if(command == 8'd7) begin

	       // the first two bytes of a port command always have the same meaning ...
               if(state == 4'd0) begin
		  // first byte is the subcommand
		  port_cmd <= data_in;
		  // return the number of ports implemented in this core
		  data_out <= 8'd1;
	       end else if(state == 4'd1) begin
		  // second byte is the port index (if several ports are supported)
		  port_index <= data_in;
		  // return port type (currently supports only 0=serial)
		  data_out <= 8'd0;
	       end else begin
		  // ... further bytes are subcommand specific

		  // port subcommand 0: get status
		  if(port_cmd == 8'd0 && port_index == 8'd0) begin
		     if(state == 4'd2)       data_out <= port_out_available;
		     else if(state == 4'd3)  data_out <= port_in_available;
		     // port status for type 0 (serial) is still close to the format
		     // that was introduced with the first MiST
		     else if(state == 4'd4)  data_out <= port_status[31:24];  // bitrate[7:0]
		     else if(state == 4'd5)  data_out <= port_status[23:16];  // bitrate[15:8]
		     else if(state == 4'd6)  data_out <= port_status[15:8];   // bitrate[23:16]
		     else if(state == 4'd7)  data_out <= port_status[7:0];    // databits, parity and stopbits
		     else                    data_out <= 8'h00;
		  end
		  
		  // port subcommand 1: read port data
		  else if(port_cmd == 8'd1 && port_index == 8'd0) begin
		     data_out <= port_out_data;

		     // reading the byte ack's the mfp's fifo. Since the
		     // data arrives with one byte delay at the MCU we need
		     // to make sure that the last read will not trigger
		     // another fifo read. The MCU will thus not set bit[0] for
		     // the last read to suppress the fifo read
		     port_out_strobe <= data_in[0];
		  end
		  
		  // port subcommand 2: write port data
		  else if(port_cmd == 8'd2 && port_index == 8'd0) begin
		     port_in_data <= data_in;
		     port_in_strobe <= 1'b1;
		  end
		  
	       end
            end // if (command == 8'd7)
	   
            // CMD 8: read (menu) config
            if(command == 8'd8) begin
	       data_out <= menu_rom_data;
	       menu_rom_addr <= menu_rom_addr + 12'd1;
	    end
	   
	end
      end // if (data_in_strobe)
   end
end
    
endmodule
