/*
    hid.v
 
    hid (keyboard, mouse etc) interface to the IO MCU
  */

module hid (
  input		   clk,
  input		   reset,

  input		   data_in_strobe,
  input		   data_in_start,
  input [7:0]      data_in,
  output reg [7:0] data_out,

  // input local db9 port events to be sent to MCU
  input  [5:0]    db9_port,
  output reg	  irq,
  input			  iack,

  // output HID data received from USB
  output [5:0]     mouse,
  output reg [7:0] keyboard[14:0],
  output reg [7:0] joystick [4]
);

reg [1:0] mouse_btns;
reg [1:0] mouse_x;
reg [1:0] mouse_y;

assign mouse = { mouse_btns, mouse_x, mouse_y };

// limit the rate at which mouse movement data is sent to the
// ikbd
reg [14:0] mouse_div;
reg [3:0] state;
reg [7:0] command;  
reg [7:0] device;   // used for joystick
   
reg [7:0] mouse_x_cnt;
reg [7:0] mouse_y_cnt;

reg irq_enable;
reg [5:0] db9_portD;
reg [5:0] db9_portD2;

// translate incoming HID key codes into
// Atari ST key matrix positions
wire [2:0] kbd_row;
wire [3:0] kbd_column;   
keymap keymap (
       .code   ( data_in[6:0] ),
       .row    ( kbd_row      ),
       .column ( kbd_column   )
);  
   
// process mouse events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;
      mouse_div <= 15'd0;
      irq <= 1'b0;
      irq_enable <= 1'b0;

      // by default no joystick is touched
      joystick[0] <= 8'h00;
      joystick[1] <= 8'h00;
      joystick[2] <= 8'h00;
      joystick[3] <= 8'h00;      
      
      // reset entire keyboard to 1's
      keyboard[ 0] <= 8'hff; keyboard[ 1] <= 8'hff; keyboard[ 2] <= 8'hff;
      keyboard[ 3] <= 8'hff; keyboard[ 4] <= 8'hff; keyboard[ 5] <= 8'hff;
      keyboard[ 6] <= 8'hff; keyboard[ 7] <= 8'hff; keyboard[ 8] <= 8'hff;
      keyboard[ 9] <= 8'hff; keyboard[10] <= 8'hff; keyboard[11] <= 8'hff;
      keyboard[12] <= 8'hff; keyboard[13] <= 8'hff; keyboard[14] <= 8'hff;      

   end else begin
      // bring db9 data into local clock domain
      db9_portD <= db9_port;
      db9_portD2 <= db9_portD;
      
      // monitor db9 port for changes and raise interrupt
      if(irq_enable) begin
        if(db9_portD2 != db9_portD) begin
            // irq_enable prevents further interrupts until
            // the db9 state has actually been read by the MCU
            irq <= 1'b1;
            irq_enable <= 1'b0;
        end
      end

      if(iack) irq <= 1'b0;      // iack clears interrupt

      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd0;
            command <= data_in;
        end else begin
            if(state != 4'd15) state <= state + 4'd1;
	    
            // CMD 0: status data
            if(command == 8'd0) begin
                if(state == 4'd0) data_out <= 8'h01;   // version 1
                if(state == 4'd1) data_out <= 8'h00;   // subversion 0
            end
	   
            // CMD 1: keyboard data
            if(command == 8'd1) begin
	       // kbd_column and kbd_row are derived from data_in
               if(state == 4'd0) keyboard[kbd_column][kbd_row] <= data_in[7]; 
            end
	       
            // CMD 2: mouse data
            if(command == 8'd2) begin
                if(state == 4'd0) mouse_btns <= data_in[1:0];
                if(state == 4'd1) mouse_x_cnt <= mouse_x_cnt + data_in;
                if(state == 4'd2) mouse_y_cnt <= mouse_y_cnt + data_in;
            end

            // CMD 3: receive digital joystick data
            if(command == 8'd3) begin
               if(state == 4'd0) device <= data_in;
               if(state == 4'd1 && device <= 8'd4) 
		 joystick[device] <= data_in;
            end

            // CMD 4: send digital joystick data to MCU
            if(command == 8'd4) begin
                if(state == 4'd0) irq_enable <= 1'b1;    // (re-)enable interrupt
                data_out <= {2'b00, db9_portD };               
            end

        end
      end else begin // if (data_in_strobe)
        mouse_div <= mouse_div + 15'd1;      
        if(mouse_div == 15'd0) begin
            if(mouse_x_cnt != 8'd0) begin
                if(mouse_x_cnt[7]) begin
                    mouse_x_cnt <= mouse_x_cnt + 8'd1;
                    // 2 bit gray counter to emulate the mouse's light barriers
                    mouse_x[0] <=  mouse_x[1];
                    mouse_x[1] <= ~mouse_x[0];		  
                end else begin
                    mouse_x_cnt <= mouse_x_cnt - 8'd1;
                    mouse_x[0] <= ~mouse_x[1];
                    mouse_x[1] <=  mouse_x[0];
                end	    
            end // if (mouse_x_cnt != 8'd0)
	    
            if(mouse_y_cnt != 8'd0) begin
                if(mouse_y_cnt[7]) begin
                    mouse_y_cnt <= mouse_y_cnt + 8'd1;
                    mouse_y[0] <=  mouse_y[1];
                    mouse_y[1] <= ~mouse_y[0];		  
                end else begin
                    mouse_y_cnt <= mouse_y_cnt - 8'd1;
                    mouse_y[0] <= ~mouse_y[1];
                    mouse_y[1] <=  mouse_y[0];
                end	    
            end
        end
      end
   end
end
    
endmodule
