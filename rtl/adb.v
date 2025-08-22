module adb(
  input CLK_14M,
  input cen,
  input reset,
  input [7:0] addr,
  input rw,
  input [7:0] din,
  output reg [7:0] dout,
  output irq,
  input strobe,
  input [10:0] ps2_key,
  input [24:0] ps2_mouse,
  output reg CLR80COL,
  output reg STORE80,
  output reg RAMRD,
  output reg RAMWRT,
  output reg ALTZP,
  output reg capslock,
  input selftest_override,
  output reg open_apple,
  output reg closed_apple,
  output reg apple_shift,
  output reg apple_ctrl,
  output reg akd,
  output reg [7:0] K
);

// Version parameter - set based on ROM type
`ifdef ROM3
  parameter VERSION = 3;  // ROM3 and later
`else
  parameter VERSION = 1;  // ROM1
`endif

// State machine states (from working stub)
parameter
  IDLE = 2'd0,
  CMD = 2'd1,
  DATA = 2'd2;

reg [1:0] state;
reg soft_reset;

// Core ADB registers (minimal set from stub)
reg [7:0] interrupt;
reg pending_irq;
reg [2:0] pending_data;
reg [31:0] data;
reg [7:0] cmd;
reg [3:0] cmd_len;
reg [63:0] cmd_data;

// Device configuration registers
reg [7:0] adb_mode;
reg [7:0] kbd_ctl_addr = 8'd2;
reg [7:0] mouse_ctl_addr = 8'd3;
reg [7:0] repeat_rate, repeat_delay;
reg [7:0] char_set = 8'd0;
reg [7:0] layout = 8'd0;
reg [7:0] repeat_info = 8'h23;

// Interrupt and status flags
reg data_int, mouse_int, kbd_int;
reg valid_mouse_data;
reg valid_kbd;
reg mouse_coord;
reg cmd_full;

// IRQ generation
wire data_irq = data_int & (pending_data > 0);
wire mouse_irq = mouse_int & valid_mouse_data;
wire kbd_irq = kbd_int & valid_kbd;
assign irq = data_irq | mouse_irq | kbd_irq;

// Internal RAM for device registers
reg [7:0] ram[255:0];

// Apple IIe compatibility registers
reg [7:0] c025;

// PS/2 input handling and state tracking
reg [10:0] ps2_key_prev;
reg [24:0] ps2_mouse_prev;
reg ps2_key_toggle_prev, ps2_mouse_toggle_prev;

// Modifier key states
reg shift_down, ctrl_down, cmd_down, option_down;
reg caps_lock_state;

// PS/2 to Apple IIgs keyboard translation function
function [7:0] ps2_to_apple_key;
  input [8:0] ps2_scancode;  // ps2_key[8:0] - includes extended bit
  begin
    case(ps2_scancode) // PS/2 Scan Code Set 2 to Apple IIgs translation
      9'h000: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h001: ps2_to_apple_key = 8'h65;  // F9
      9'h002: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h003: ps2_to_apple_key = 8'h60;  // F5
      9'h004: ps2_to_apple_key = 8'h63;  // F3
      9'h005: ps2_to_apple_key = 8'h7A;  // F1
      9'h006: ps2_to_apple_key = 8'h78;  // F2
      9'h007: ps2_to_apple_key = 8'h7F;  // F12 (unmapped)
      9'h008: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h009: ps2_to_apple_key = 8'h6D;  // F10
      9'h00a: ps2_to_apple_key = 8'h64;  // F8
      9'h00b: ps2_to_apple_key = 8'h61;  // F6
      9'h00c: ps2_to_apple_key = 8'h76;  // F4
      9'h00d: ps2_to_apple_key = 8'h30;  // TAB
      9'h00e: ps2_to_apple_key = 8'h32;  // ~ (`)
      9'h00f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h010: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h011: ps2_to_apple_key = 8'h37;  // LEFT ALT (command)
      9'h012: ps2_to_apple_key = 8'h38;  // LEFT SHIFT
      9'h013: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h014: ps2_to_apple_key = 8'h36;  // CTRL
      9'h015: ps2_to_apple_key = 8'h0C;  // Q
      9'h016: ps2_to_apple_key = 8'h12;  // 1
      9'h017: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h018: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h019: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h01a: ps2_to_apple_key = 8'h06;  // Z
      9'h01b: ps2_to_apple_key = 8'h01;  // S
      9'h01c: ps2_to_apple_key = 8'h00;  // A
      9'h01d: ps2_to_apple_key = 8'h0D;  // W
      9'h01e: ps2_to_apple_key = 8'h13;  // 2
      9'h01f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h020: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h021: ps2_to_apple_key = 8'h08;  // C
      9'h022: ps2_to_apple_key = 8'h07;  // X
      9'h023: ps2_to_apple_key = 8'h02;  // D
      9'h024: ps2_to_apple_key = 8'h0E;  // E
      9'h025: ps2_to_apple_key = 8'h15;  // 4
      9'h026: ps2_to_apple_key = 8'h14;  // 3
      9'h027: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h028: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h029: ps2_to_apple_key = 8'h31;  // SPACE
      9'h02a: ps2_to_apple_key = 8'h09;  // V
      9'h02b: ps2_to_apple_key = 8'h03;  // F
      9'h02c: ps2_to_apple_key = 8'h11;  // T
      9'h02d: ps2_to_apple_key = 8'h0F;  // R
      9'h02e: ps2_to_apple_key = 8'h17;  // 5
      9'h02f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h030: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h031: ps2_to_apple_key = 8'h2D;  // N
      9'h032: ps2_to_apple_key = 8'h0B;  // B
      9'h033: ps2_to_apple_key = 8'h04;  // H
      9'h034: ps2_to_apple_key = 8'h05;  // G
      9'h035: ps2_to_apple_key = 8'h10;  // Y
      9'h036: ps2_to_apple_key = 8'h16;  // 6
      9'h037: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h038: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h039: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h03a: ps2_to_apple_key = 8'h2E;  // M
      9'h03b: ps2_to_apple_key = 8'h26;  // J
      9'h03c: ps2_to_apple_key = 8'h20;  // U
      9'h03d: ps2_to_apple_key = 8'h1A;  // 7
      9'h03e: ps2_to_apple_key = 8'h1C;  // 8
      9'h03f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h040: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h041: ps2_to_apple_key = 8'h2B;  // < (,)
      9'h042: ps2_to_apple_key = 8'h28;  // K
      9'h043: ps2_to_apple_key = 8'h22;  // I
      9'h044: ps2_to_apple_key = 8'h1F;  // O
      9'h045: ps2_to_apple_key = 8'h1D;  // 0
      9'h046: ps2_to_apple_key = 8'h19;  // 9
      9'h047: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h048: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h049: ps2_to_apple_key = 8'h2F;  // > (.)
      9'h04a: ps2_to_apple_key = 8'h2C;  // FORWARD SLASH
      9'h04b: ps2_to_apple_key = 8'h25;  // L
      9'h04c: ps2_to_apple_key = 8'h29;  // ;
      9'h04d: ps2_to_apple_key = 8'h23;  // P
      9'h04e: ps2_to_apple_key = 8'h1B;  // - (minus)
      9'h04f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h050: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h051: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h052: ps2_to_apple_key = 8'h27;  // ' ("")
      9'h053: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h054: ps2_to_apple_key = 8'h21;  // [
      9'h055: ps2_to_apple_key = 8'h18;  // = 
      9'h056: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h057: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h058: ps2_to_apple_key = 8'h39;  // CAPSLOCK
      9'h059: ps2_to_apple_key = 8'h7B;  // RIGHT SHIFT
      9'h05a: ps2_to_apple_key = 8'h24;  // ENTER
      9'h05b: ps2_to_apple_key = 8'h1E;  // ]
      9'h05c: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h05d: ps2_to_apple_key = 8'h2A;  // BACKSLASH
      9'h05e: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h05f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h060: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h061: ps2_to_apple_key = 8'h7F;  // International left shift (German <> key)
      9'h062: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h063: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h064: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h065: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h066: ps2_to_apple_key = 8'h33;  // BACKSPACE
      9'h067: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h068: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h069: ps2_to_apple_key = 8'h53;  // KP 1
      9'h06a: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h06b: ps2_to_apple_key = 8'h56;  // KP 4
      9'h06c: ps2_to_apple_key = 8'h59;  // KP 7
      9'h06d: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h06e: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h06f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h070: ps2_to_apple_key = 8'h52;  // KP 0
      9'h071: ps2_to_apple_key = 8'h41;  // KP .
      9'h072: ps2_to_apple_key = 8'h54;  // KP 2
      9'h073: ps2_to_apple_key = 8'h57;  // KP 5
      9'h074: ps2_to_apple_key = 8'h58;  // KP 6
      9'h075: ps2_to_apple_key = 8'h5B;  // KP 8
      9'h076: ps2_to_apple_key = 8'h35;  // ESCAPE
      9'h077: ps2_to_apple_key = 8'h47;  // NUMLOCK (Mac keypad clear)
      9'h078: ps2_to_apple_key = 8'h67;  // F11
      9'h079: ps2_to_apple_key = 8'h45;  // KP +
      9'h07a: ps2_to_apple_key = 8'h55;  // KP 3
      9'h07b: ps2_to_apple_key = 8'h4E;  // KP -
      9'h07c: ps2_to_apple_key = 8'h43;  // KP *
      9'h07d: ps2_to_apple_key = 8'h5C;  // KP 9
      9'h07e: ps2_to_apple_key = 8'h7F;  // SCROLL LOCK
      9'h07f: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h080: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h081: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h082: ps2_to_apple_key = 8'h7F;  // Invalid
      9'h083: ps2_to_apple_key = 8'h62;  // F7
      9'h084: ps2_to_apple_key = 8'h7F;  // Invalid
      // Extended keys (ps2_key[8] = 1) - these require special handling
      9'h111: ps2_to_apple_key = 8'h37;  // RIGHT ALT (command)
      9'h114: ps2_to_apple_key = 8'h36;  // RIGHT CTRL (extended ctrl)
      9'h11f: ps2_to_apple_key = 8'h3A;  // WINDOWS/APPLICATION KEY (option)
      9'h127: ps2_to_apple_key = 8'h3A;  // MENU KEY (option)
      9'h14a: ps2_to_apple_key = 8'h4B;  // KP /
      9'h15a: ps2_to_apple_key = 8'h4C;  // KP ENTER
      9'h169: ps2_to_apple_key = 8'h77;  // END
      9'h16b: ps2_to_apple_key = 8'h3B;  // ARROW LEFT
      9'h16c: ps2_to_apple_key = 8'h73;  // HOME
      9'h170: ps2_to_apple_key = 8'h72;  // INSERT (HELP)
      9'h171: ps2_to_apple_key = 8'h75;  // DELETE
      9'h172: ps2_to_apple_key = 8'h3D;  // ARROW DOWN
      9'h174: ps2_to_apple_key = 8'h3C;  // ARROW RIGHT
      9'h175: ps2_to_apple_key = 8'h3E;  // ARROW UP
      9'h17a: ps2_to_apple_key = 8'h79;  // PGDN
      9'h17c: ps2_to_apple_key = 8'h69;  // PRTSCR (F13)
      9'h17d: ps2_to_apple_key = 8'h74;  // PGUP
      9'h17e: ps2_to_apple_key = 8'h71;  // CTRL+BREAK (F15)
      default: ps2_to_apple_key = 8'h7F;  // Unmapped keys
    endcase
  end
endfunction

// Apple IIe ASCII conversion function 
function [7:0] adb_to_apple_iie_ascii;
  input [6:0] adb_key;     // ADB key code (0x00-0x7F)
  input       shift_mod;   // Shift modifier active
  input       ctrl_mod;    // Control modifier active  
  input       caps_mod;    // Caps lock active
  
  reg [7:0] normal_ascii;
  reg [7:0] shift_ascii;
  reg [7:0] ctrl_ascii;
  reg       is_letter;
  
  begin
    // Default values
    normal_ascii = 8'hFF;
    shift_ascii = 8'hFF;
    ctrl_ascii = 8'hFF;
    is_letter = 1'b0;
    
    // Basic character mappings
    case(adb_key)
      // Letters
      7'h00: begin normal_ascii = "a"; shift_ascii = "A"; ctrl_ascii = 8'h01; is_letter = 1'b1; end // A
      7'h01: begin normal_ascii = "s"; shift_ascii = "S"; ctrl_ascii = 8'h13; is_letter = 1'b1; end // S
      7'h02: begin normal_ascii = "d"; shift_ascii = "D"; ctrl_ascii = 8'h04; is_letter = 1'b1; end // D
      7'h03: begin normal_ascii = "f"; shift_ascii = "F"; ctrl_ascii = 8'h06; is_letter = 1'b1; end // F
      7'h04: begin normal_ascii = "h"; shift_ascii = "H"; ctrl_ascii = 8'h08; is_letter = 1'b1; end // H
      7'h05: begin normal_ascii = "g"; shift_ascii = "G"; ctrl_ascii = 8'h07; is_letter = 1'b1; end // G
      7'h06: begin normal_ascii = "z"; shift_ascii = "Z"; ctrl_ascii = 8'h1A; is_letter = 1'b1; end // Z
      7'h07: begin normal_ascii = "x"; shift_ascii = "X"; ctrl_ascii = 8'h18; is_letter = 1'b1; end // X
      7'h08: begin normal_ascii = "c"; shift_ascii = "C"; ctrl_ascii = 8'h03; is_letter = 1'b1; end // C
      7'h09: begin normal_ascii = "v"; shift_ascii = "V"; ctrl_ascii = 8'h16; is_letter = 1'b1; end // V
      7'h0B: begin normal_ascii = "b"; shift_ascii = "B"; ctrl_ascii = 8'h02; is_letter = 1'b1; end // B
      7'h0C: begin normal_ascii = "q"; shift_ascii = "Q"; ctrl_ascii = 8'h11; is_letter = 1'b1; end // Q
      7'h0D: begin normal_ascii = "w"; shift_ascii = "W"; ctrl_ascii = 8'h17; is_letter = 1'b1; end // W
      7'h0E: begin normal_ascii = "e"; shift_ascii = "E"; ctrl_ascii = 8'h05; is_letter = 1'b1; end // E
      7'h0F: begin normal_ascii = "r"; shift_ascii = "R"; ctrl_ascii = 8'h12; is_letter = 1'b1; end // R
      7'h10: begin normal_ascii = "y"; shift_ascii = "Y"; ctrl_ascii = 8'h19; is_letter = 1'b1; end // Y
      7'h11: begin normal_ascii = "t"; shift_ascii = "T"; ctrl_ascii = 8'h14; is_letter = 1'b1; end // T
      7'h1F: begin normal_ascii = "o"; shift_ascii = "O"; ctrl_ascii = 8'h0F; is_letter = 1'b1; end // O
      7'h20: begin normal_ascii = "u"; shift_ascii = "U"; ctrl_ascii = 8'h15; is_letter = 1'b1; end // U
      7'h22: begin normal_ascii = "i"; shift_ascii = "I"; ctrl_ascii = 8'h09; is_letter = 1'b1; end // I
      7'h23: begin normal_ascii = "p"; shift_ascii = "P"; ctrl_ascii = 8'h10; is_letter = 1'b1; end // P
      7'h25: begin normal_ascii = "l"; shift_ascii = "L"; ctrl_ascii = 8'h0C; is_letter = 1'b1; end // L
      7'h26: begin normal_ascii = "j"; shift_ascii = "J"; ctrl_ascii = 8'h0A; is_letter = 1'b1; end // J
      7'h28: begin normal_ascii = "k"; shift_ascii = "K"; ctrl_ascii = 8'h0B; is_letter = 1'b1; end // K
      7'h2D: begin normal_ascii = "n"; shift_ascii = "N"; ctrl_ascii = 8'h0E; is_letter = 1'b1; end // N
      7'h2E: begin normal_ascii = "m"; shift_ascii = "M"; ctrl_ascii = 8'h0D; is_letter = 1'b1; end // M
      
      // Numbers
      7'h12: begin normal_ascii = "1"; shift_ascii = "!"; ctrl_ascii = 8'hFF; end // 1
      7'h13: begin normal_ascii = "2"; shift_ascii = "@"; ctrl_ascii = 8'h00; end // 2  
      7'h14: begin normal_ascii = "3"; shift_ascii = "#"; ctrl_ascii = 8'hFF; end // 3
      7'h15: begin normal_ascii = "4"; shift_ascii = "$"; ctrl_ascii = 8'hFF; end // 4
      7'h17: begin normal_ascii = "5"; shift_ascii = "%"; ctrl_ascii = 8'hFF; end // 5
      7'h16: begin normal_ascii = "6"; shift_ascii = "^"; ctrl_ascii = 8'h1E; end // 6
      7'h1A: begin normal_ascii = "7"; shift_ascii = "&"; ctrl_ascii = 8'hFF; end // 7
      7'h1C: begin normal_ascii = "8"; shift_ascii = "*"; ctrl_ascii = 8'hFF; end // 8
      7'h19: begin normal_ascii = "9"; shift_ascii = "("; ctrl_ascii = 8'hFF; end // 9
      7'h1D: begin normal_ascii = "0"; shift_ascii = ")"; ctrl_ascii = 8'hFF; end // 0
      
      // Special keys
      7'h35: begin normal_ascii = 8'h1B; shift_ascii = 8'h1B; ctrl_ascii = 8'hFF; end // ESC
      7'h30: begin normal_ascii = 8'h09; shift_ascii = 8'h09; ctrl_ascii = 8'hFF; end // TAB
      7'h31: begin normal_ascii = 8'h20; shift_ascii = 8'h20; ctrl_ascii = 8'hFF; end // SPACE
      7'h24: begin normal_ascii = 8'h0D; shift_ascii = 8'h0D; ctrl_ascii = 8'hFF; end // RETURN
      7'h33: begin normal_ascii = 8'h7F; shift_ascii = 8'h7F; ctrl_ascii = 8'hFF; end // DELETE
      
      // Punctuation
      7'h29: begin normal_ascii = ";"; shift_ascii = ":"; ctrl_ascii = 8'hFF; end // ;
      7'h27: begin normal_ascii = "'"; shift_ascii = "\""; ctrl_ascii = 8'hFF; end // '
      7'h21: begin normal_ascii = "["; shift_ascii = "{"; ctrl_ascii = 8'h1B; end // [
      7'h1E: begin normal_ascii = "]"; shift_ascii = "}"; ctrl_ascii = 8'h1D; end // ]
      7'h2A: begin normal_ascii = 8'h5C; shift_ascii = "|"; ctrl_ascii = 8'h1C; end // \
      7'h2B: begin normal_ascii = ","; shift_ascii = "<"; ctrl_ascii = 8'hFF; end // ,
      7'h2F: begin normal_ascii = "."; shift_ascii = ">"; ctrl_ascii = 8'hFF; end // .
      7'h2C: begin normal_ascii = "/"; shift_ascii = "?"; ctrl_ascii = 8'h7F; end // /
      7'h32: begin normal_ascii = "`"; shift_ascii = "~"; ctrl_ascii = 8'hFF; end // `
      7'h1B: begin normal_ascii = "-"; shift_ascii = "_"; ctrl_ascii = 8'h1F; end // -
      7'h18: begin normal_ascii = "="; shift_ascii = "+"; ctrl_ascii = 8'hFF; end // =
      
      // Arrow keys
      7'h3B: begin normal_ascii = 8'h08; shift_ascii = 8'h08; ctrl_ascii = 8'hFF; end // LEFT
      7'h3C: begin normal_ascii = 8'h15; shift_ascii = 8'h15; ctrl_ascii = 8'hFF; end // RIGHT  
      7'h3D: begin normal_ascii = 8'h0A; shift_ascii = 8'h0A; ctrl_ascii = 8'hFF; end // DOWN
      7'h3E: begin normal_ascii = 8'h0B; shift_ascii = 8'h0B; ctrl_ascii = 8'hFF; end // UP
      
      default: begin 
        normal_ascii = 8'hFF; 
        shift_ascii = 8'hFF; 
        ctrl_ascii = 8'hFF; 
      end
    endcase
    
    // Apply modifier logic
    if (ctrl_mod && ctrl_ascii != 8'hFF) begin
      adb_to_apple_iie_ascii = ctrl_ascii;
    end else if (caps_mod && is_letter && normal_ascii >= "a" && normal_ascii <= "z") begin
      adb_to_apple_iie_ascii = shift_ascii;  // Caps lock = uppercase
    end else if (shift_mod) begin
      adb_to_apple_iie_ascii = (shift_ascii != 8'hFF) ? shift_ascii : normal_ascii;
    end else begin
      adb_to_apple_iie_ascii = normal_ascii;
    end
  end
endfunction

always @(posedge CLK_14M) begin

  // Reset handling
  if (reset | soft_reset) begin
    soft_reset <= 1'b0;
    data_int <= 1'b1;
    mouse_int <= 1'b0;
    kbd_int <= 1'b0;
    state <= IDLE;
    pending_data <= 3'd0;
    pending_irq <= 1'b0;
    cmd_full <= 1'b0;
    valid_mouse_data <= 1'b0;
    valid_kbd <= 1'b0;
    mouse_coord <= 1'b0;
    
    // Initialize device addresses
    kbd_ctl_addr <= 8'd2;
    mouse_ctl_addr <= 8'd3;
    adb_mode <= 8'd0;
    repeat_info <= 8'h23;
    char_set <= 8'd0;
    layout <= 8'd0;
    
    // PS/2 input tracking
    ps2_key_toggle_prev <= 1'b0;
    ps2_mouse_toggle_prev <= 1'b0;
    
    // Modifier key states
    shift_down <= 1'b0;
    ctrl_down <= 1'b0;
    cmd_down <= 1'b0;
    option_down <= 1'b0;
    caps_lock_state <= 1'b0;
    
    // Apple IIe compatibility
    CLR80COL <= 1'b0;
    STORE80 <= 1'b0;
    RAMRD <= 1'b0;
    RAMWRT <= 1'b0;
    ALTZP <= 1'b0;
    
    // Keyboard status outputs
    capslock <= 1'b0;
    open_apple <= 1'b0;
    closed_apple <= 1'b0;
    apple_shift <= 1'b0;
    apple_ctrl <= 1'b0;
    akd <= 1'b0;
    K <= 8'd0;
  end else begin
    
    // Track PS/2 input changes
    ps2_key_prev <= ps2_key;
    ps2_mouse_prev <= ps2_mouse;
    ps2_key_toggle_prev <= ps2_key[10];
    ps2_mouse_toggle_prev <= ps2_mouse[24];
    
    // PS/2 keyboard event processing  
    if (ps2_key[10] != ps2_key_toggle_prev) begin
      // PS/2 key event detected - using wire for combinational logic
      
      // Handle Caps Lock toggle
      if (ps2_key[8:0] == 9'h058 && ps2_key[9]) begin  // Caps Lock pressed
        caps_lock_state <= ~caps_lock_state;
        capslock <= ~caps_lock_state;
      end
      
      // Handle modifier keys
      case(ps2_key[8:0])
        9'h012, 9'h059: begin  // Left/Right Shift
          shift_down <= ps2_key[9];
          apple_shift <= ps2_key[9];
        end
        9'h014, 9'h114: begin  // Left/Right Ctrl
          ctrl_down <= ps2_key[9];
          apple_ctrl <= ps2_key[9];
        end
        9'h011, 9'h111: begin  // Left/Right Alt (Command)
          cmd_down <= ps2_key[9];
          open_apple <= ps2_key[9];
        end
        9'h11f, 9'h127: begin  // Windows/Menu keys (Option)
          option_down <= ps2_key[9];
          closed_apple <= ps2_key[9];
        end
      endcase
      
      // Process normal keys (not modifier keys)
      begin
        reg [7:0] temp_apple_key;
        reg [7:0] temp_iie_char;
        
        temp_apple_key = ps2_to_apple_key(ps2_key[8:0]);
        
        if (temp_apple_key != 8'h7F && !(ps2_key[8:0] == 9'h058)) begin
          if (ps2_key[9]) begin  // Key pressed (not released)
            temp_iie_char = adb_to_apple_iie_ascii(
              temp_apple_key[6:0], 
              shift_down, 
              ctrl_down, 
              caps_lock_state
            );
            
            // Update Apple IIe compatibility registers
            if (temp_iie_char != 8'hFF) begin
              K <= {1'b1, temp_iie_char[6:0]};  // Set strobe bit + 7-bit ASCII
              akd <= 1'b1;  // Any key down
            end
            
            // Set keyboard interrupt flag
            valid_kbd <= 1'b1;
          end else begin
            // Key released
            akd <= 1'b0;  // Clear any key down
          end
        end
      end
    end
    
    // PS/2 mouse event processing
    if (ps2_mouse[24] != ps2_mouse_toggle_prev) begin
      if (ps2_mouse[7:0] != 8'h00) begin
        // Mouse data available
        valid_mouse_data <= 1'b1;
      end
    end
    
    // Address decoding and register access
    case (addr)

      8'h25: begin
        if (rw) begin
          dout <= c025;
        end else if (cen & strobe) begin
          c025 <= din;
        end
      end

      8'h26: begin
        // Read $C026 - ADB Command/Data Register
        if (rw) begin
          case (state)
            IDLE: begin
              dout <= data[7:0];
              if (pending_irq) dout <= 8'b0001_0000;
              if (pending_data > 3'd0) state <= DATA;
            end
            CMD: dout <= 8'd0;
            DATA: begin
              dout <= data[7:0];
              if (cen & strobe) begin
                data <= { 8'd0, data[31:8] };
                if (pending_data > 3'd0) pending_data <= pending_data - 3'd1;
                if (pending_data == 3'd1) state <= IDLE;
              end
            end
          endcase
        end
        // Write $C026 - ADB Commands
        else if (cen & strobe) begin
          case (state)

            IDLE: begin
              cmd <= din;
              
              case (din)
                8'h01: ; // abort
                8'h03: ; // flush keyboard buffer
                8'h04: begin cmd_len <= 4'd1; state <= CMD; end
                8'h05: begin cmd_len <= 4'd1; state <= CMD; end
                8'h06: begin cmd_len <= 4'd3; state <= CMD; end
                8'h07: begin 
                  // SYNC command - length depends on version
                  cmd_len <= (VERSION == 1) ? 4'd4 : 4'd8; 
                  state <= CMD; 
                end
                8'h08: begin cmd_len <= 4'd2; state <= CMD; end
                8'h09: begin cmd_len <= 4'd2; state <= CMD; end
                8'h0a: begin
                  // Read ADB modes
                  data <= { 24'd0, adb_mode };
                  pending_data <= 3'd1;
                end
                8'h0b: begin
                  // Read device info
                  data <= {
                    mouse_ctl_addr,
                    kbd_ctl_addr,
                    char_set,
                    layout
                  };
                  pending_data <= 3'd4;
                end
                8'h0d: begin
                  // Read ADB version
                  data <= { 24'd0, (VERSION == 1 ? 8'd5 : 8'd6) };
                  pending_data <= 3'd1;
                end
                8'h0e: begin 
                  // Read charsets
                  data <= { 16'd0, 8'd0, 8'd1 };
                  pending_data <= 3'd2;
                end
                8'h0f: begin 
                  // Read layouts
                  data <= { 16'd0, 8'd0, 8'h1 };
                  pending_data <= 3'd2;
                end
                8'h10: soft_reset <= 1'b1;
                8'h11: begin cmd_len <= 4'd1; state <= CMD; end
                8'h12: if (VERSION >= 3) begin cmd_len <= 4'd2; state <= CMD; end
                8'h13: if (VERSION >= 3) begin cmd_len <= 4'd2; state <= CMD; end
                8'h73: ; // disable SRQ on mouse
                8'hb0, 8'hb1, 8'hb2, 8'hb3,
                8'hb4, 8'hb5, 8'hb6, 8'hb7,
                8'hb8, 8'hb9, 8'hba, 8'hbb,
                8'hbc, 8'hbd, 8'hbe, 8'hbf: begin
                  cmd_len <= 4'd2;
                  state <= CMD;
                end
                8'hc0, 8'hc1, 8'hc2, 8'hc3,
                8'hc4, 8'hc5, 8'hc6, 8'hc7,
                8'hc8, 8'hc9, 8'hca, 8'hcb,
                8'hcc, 8'hcd, 8'hce, 8'hcf:
                  if (din[3:0] == kbd_ctl_addr[3:0]) begin
                    // ADB keyboard talk
                  end
                8'hf0, 8'hf1, 8'hf2, 8'hf3,
                8'hf4, 8'hf5, 8'hf6, 8'hf7,
                8'hf8, 8'hf9, 8'hfa, 8'hfb,
                8'hfc, 8'hfd, 8'hfe, 8'hff:
                  if (din[3:0] == kbd_ctl_addr[3:0]) begin
                    // ADB response packet
                  end
              endcase
            end

            CMD: begin
              cmd_data[(cmd_len-1)*8+:8] <= din;

              // Process command when enough data received
              if (cmd_len == 4'd1) begin
                cmd_len <= 4'd0;
                state <= IDLE;
                
                case (cmd)
                  8'h04: adb_mode <= din | adb_mode;
                  8'h05: adb_mode <= adb_mode & ~din;
                  8'h06, 8'h07: begin 
                    // SYNC/ASYNC commands
                    if (cmd[0]) adb_mode <= cmd_data[31:24] | adb_mode;
                    mouse_ctl_addr <= cmd_data[23:20];
                    kbd_ctl_addr <= cmd_data[19:16];
                    repeat_delay <= din[7] ? 8'd0 : (din[7:4]+1)*8'd15;
                    case (din[3:0])
                      4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6: repeat_rate <= din[3:0]+1;
                      4'd7: repeat_rate <= 8'd15;
                      4'd8: repeat_rate <= 8'd30;
                      4'd9: repeat_rate <= 8'd60;
                    endcase
                  end
                  8'h08: ram[cmd_data[15:8]] <= din;
                  8'h09: begin
                    data <= { 24'd0, ram[{din, cmd_data[15:8]}] };
                    pending_data <= 3'd1;
                  end
                  8'h11: ; // send keycode data
                  8'h12: if (VERSION >= 3) ; // ROM3 command
                  8'h13: if (VERSION >= 3) ; // ROM3 command
                  8'hb0, 8'hb1, 8'hb2, 8'hb3,
                  8'hb4, 8'hb5, 8'hb6, 8'hb7,
                  8'hb8, 8'hb9, 8'hba, 8'hbb,
                  8'hbc, 8'hbd, 8'hbe, 8'hbf:
                    if (cmd[3:0] == kbd_ctl_addr[3:0]) begin
                      // Keyboard command processing
                    end
                    else if (cmd[3:0] == mouse_ctl_addr[3:0]) begin
                      // Mouse command processing
                    end
                endcase
              end
              else begin
                cmd_len <= cmd_len - 4'd1;
              end
            end
          endcase
        end
      end

      8'h27: begin
        // Read/Write $C027 - ADB Status Register
        if (rw) begin
          dout <= {
            valid_mouse_data,
            mouse_int,
            pending_data > 0 ? 1'b1 : 1'b0,
            data_int,
            valid_kbd,
            kbd_int,
            mouse_coord,
            cmd_full
          };
        end
        else if (cen & strobe) begin
          mouse_int <= din[6];
          data_int <= din[4];
          kbd_int <= din[2];
        end
      end

      // Apple IIe keyboard compatibility registers
      8'h00: begin  // $C000 - Keyboard data
        if (rw) begin
          dout <= K;  // Return key with strobe bit
        end
      end
      
      8'h10: begin  // $C010 - Keyboard strobe clear
        if (rw) begin
          dout <= K;
        end else if (cen & strobe) begin
          K <= {1'b0, K[6:0]};  // Clear strobe bit
          akd <= 1'b0;  // Clear any key down
        end
      end
      
      // Paddle/Joystick registers (stub)
      8'h60, 8'h61, 8'h62, 8'h63: begin
        dout <= 8'd0;
      end

      8'h64, 8'h65, 8'h66, 8'h67: begin
        dout <= 8'd0;
      end

      default: dout <= 8'd0;
    endcase
  end
end

endmodule