/*
 atarist_keymap.v
 
 table to translate from FPGA Compantions key codes into the 
 Atari ST keyboard matrix. The incoming FPGA Companion codes
 are mainly the USB HID key codes with the modifier keys
 mapped into the 0x68+ range.
*/

module keymap (
  input [6:0]  code,
  output [2:0] row,
  output [3:0] column
);

assign { column, row }
= 
                                // 00: NoEvent
                                // 01: Overrun Error
                                // 02: POST fail
                                // 03: ErrorUndefined
  
  // characters
  (code == 7'h04)?{ 4'd4,3'd5}: // 04: a
  (code == 7'h05)?{ 4'd7,3'd6}: // 05: b
  (code == 7'h06)?{ 4'd6,3'd6}: // 06: c
  (code == 7'h07)?{ 4'd5,3'd6}: // 07: d
  (code == 7'h08)?{ 4'd5,3'd4}: // 08: e
  (code == 7'h09)?{ 4'd6,3'd5}: // 09: f
  (code == 7'h0a)?{ 4'd7,3'd4}: // 0a: g
  (code == 7'h0b)?{ 4'd7,3'd5}: // 0b: h
  (code == 7'h0c)?{ 4'd8,3'd4}: // 0c: i
  (code == 7'h0d)?{ 4'd8,3'd5}: // 0d: j
  (code == 7'h0e)?{ 4'd8,3'd6}: // 0e: k
  (code == 7'h0f)?{ 4'd9,3'd5}: // 0f: l
  (code == 7'h10)?{ 4'd8,3'd7}: // 10: m
  (code == 7'h11)?{ 4'd7,3'd7}: // 11: n
  (code == 7'h12)?{ 4'd9,3'd3}: // 12: o
  (code == 7'h13)?{ 4'd9,3'd4}: // 13: p
  (code == 7'h14)?{ 4'd4,3'd4}: // 14: q
  (code == 7'h15)?{ 4'd6,3'd3}: // 15: r
  (code == 7'h16)?{ 4'd5,3'd5}: // 16: s
  (code == 7'h17)?{ 4'd6,3'd4}: // 17: t
  (code == 7'h18)?{ 4'd8,3'd3}: // 18: u
  (code == 7'h19)?{ 4'd6,3'd7}: // 19: v
  (code == 7'h1a)?{ 4'd5,3'd3}: // 1a: w
  (code == 7'h1b)?{ 4'd5,3'd7}: // 1b: x
  (code == 7'h1c)?{ 4'd7,3'd3}: // 1c: y
  (code == 7'h1d)?{ 4'd4,3'd7}: // 1d: z

  // top number key row
  (code == 7'h1e)?{ 4'd4,3'd2}: // 1e: 1
  (code == 7'h1f)?{ 4'd5,3'd1}: // 1f: 2
  (code == 7'h20)?{ 4'd5,3'd2}: // 20: 3
  (code == 7'h21)?{ 4'd6,3'd1}: // 21: 4
  (code == 7'h22)?{ 4'd6,3'd2}: // 22: 5
  (code == 7'h23)?{ 4'd7,3'd1}: // 23: 6
  (code == 7'h24)?{ 4'd7,3'd2}: // 24: 7
  (code == 7'h25)?{ 4'd8,3'd1}: // 25: 8
  (code == 7'h26)?{ 4'd8,3'd2}: // 26: 9
  (code == 7'h27)?{ 4'd9,3'd1}: // 27: 0
  
  // other keys
  (code == 7'h28)?{4'd11,3'd5}: // 28: return
  (code == 7'h29)?{ 4'd4,3'd1}: // 29: esc
  (code == 7'h2a)?{4'd11,3'd1}: // 2a: backspace
  (code == 7'h2b)?{ 4'd4,3'd3}: // 2b: tab		  
  (code == 7'h2c)?{ 4'd9,3'd7}: // 2c: space

  (code == 7'h2d)?{ 4'd9,3'd2}: // 2d: -
  (code == 7'h2e)?{4'd10,3'd1}: // 2e: =
  (code == 7'h2f)?{4'd10,3'd3}: // 2f: [			  
  (code == 7'h30)?{4'd10,3'd4}: // 30: ]
  (code == 7'h31)?{4'd11,3'd4}: // 31: backslash 
  (code == 7'h32)?{4'd11,3'd4}: // 32: backslash on some eur keyboards(near enter)
  (code == 7'h33)?{4'd10,3'd5}: // 33: ;
  (code == 7'h34)?{4'd11,3'd6}: // 34: ' 
  (code == 7'h35)?{4'd10,3'd2}: // 35: `
  (code == 7'h36)?{ 4'd9,3'd6}: // 36: ,3'd
  (code == 7'h37)?{4'd10,3'd6}: // 37: .
  (code == 7'h38)?{4'd11,3'd7}: // 38: /
  (code == 7'h39)?{4'd10,3'd7}: // 39: caps lock
  
  // function keys
  (code == 7'h3a)?{ 4'd1,3'd0}: // 3a: F1
  (code == 7'h3b)?{ 4'd2,3'd0}: // 3b: F2
  (code == 7'h3c)?{ 4'd3,3'd0}: // 3c: F3
  (code == 7'h3d)?{ 4'd4,3'd0}: // 3d: F4
  (code == 7'h3e)?{ 4'd5,3'd0}: // 3e: F5
  (code == 7'h3f)?{ 4'd6,3'd0}: // 3f: F6
  (code == 7'h40)?{ 4'd7,3'd0}: // 40: F7
  (code == 7'h41)?{ 4'd8,3'd0}: // 41: F8
  (code == 7'h42)?{ 4'd9,3'd0}: // 42: F9
  (code == 7'h43)?{4'd10,3'd0}: // 43: F10
                                // 44: F11
                                // 45: F12

  (code == 7'h46)?{4'd13,3'd0}: // 46: PrtScr -> KP-(
                                // 47: Scroll Lock
                                // 48: Pause
  (code == 7'h49)?{4'd11,3'd3}: // 49: Insert
  (code == 7'h4a)?{4'd12,3'd2}: // 4a: Home
  (code == 7'h4b)?{4'd11,3'd0}: // 4b: PageUp -> HELP
  (code == 7'h4c)?{4'd11,3'd2}: // 4c: Delete
  (code == 7'h4d)?{4'd13,3'd1}: // 4d: End -> KP-)
  (code == 7'h4e)?{4'd12,3'd0}: // 4e: PageDown -> UNDO
  
  // cursor keys
  (code == 7'h4f)?{4'd12,3'd5}: // 4f: right
  (code == 7'h50)?{4'd12,3'd3}: // 50: left
  (code == 7'h51)?{4'd12,3'd4}: // 51: down
  (code == 7'h52)?{4'd12,3'd1}: // 52: up
  
                                // 53: Num Lock

  // keypad
  (code == 7'h54)?{4'd14,3'd0}: // 54: KP /
  (code == 7'h55)?{4'd14,3'd1}: // 55: KP *
  (code == 7'h56)?{4'd14,3'd3}: // 56: KP -
  (code == 7'h57)?{4'd14,3'd5}: // 57: KP +
  (code == 7'h58)?{4'd14,3'd7}: // 58: KP Enter
  (code == 7'h59)?{4'd12,3'd6}: // 59: KP 1
  (code == 7'h5a)?{4'd13,3'd6}: // 5a: KP 2
  (code == 7'h5b)?{4'd14,3'd6}: // 5b: KP 3
  (code == 7'h5c)?{4'd13,3'd4}: // 5c: KP 4
  (code == 7'h5d)?{4'd13,3'd5}: // 5d: KP 5
  (code == 7'h5e)?{4'd14,3'd4}: // 5e: KP 6
  (code == 7'h5f)?{4'd13,3'd2}: // 5f: KP 7
  (code == 7'h60)?{4'd13,3'd3}: // 60: KP 8
  (code == 7'h61)?{4'd14,3'd2}: // 61: KP 9
  (code == 7'h62)?{4'd12,3'd7}: // 62: KP 0
  (code == 7'h63)?{4'd13,3'd7}: // 63: KP .
  (code == 7'h64)?{ 4'd4,3'd6}: // 64: EUR-2

  // remapped modifier keys
  (code == 7'h68)?{ 4'd0,3'd4}: // 68: left ctrl
  (code == 7'h69)?{ 4'd1,3'd5}: // 69: left shift
  (code == 7'h6a)?{ 4'd2,3'd6}: // 6a: left alt
                                // 6b: left meta
  (code == 7'h6c)?{ 4'd0,3'd4}: // 6c: right ctrl
  (code == 7'h6d)?{ 4'd3,3'd7}: // 6d: right shift
                                // 6e: right alt
                                // 6f: right meta
  
  { 4'd0,3'd0};
  
endmodule
