// Define DEBUG_ADB to enable verbose ADB debug output
//`define DEBUG_ADB

module adb(
  input CLK_14M,
  input cen,
  input reset,
  input [7:0] addr,
  input rw,
  input [7:0] din,
  output reg [7:0] dout,
  output [7:0] dout_comb,  // Combinational output for same-cycle reads
  output irq,
  input strobe,
  input [10:0] ps2_key,
  input [24:0] ps2_mouse,
  input [8:0] vbl_count,   // VBL counter from video system for key repeat timing
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
  output reg [7:0] K,
  output reset_key_pressed  // Reset key (F11/0x7F) is currently pressed
);

// Version parameter - set based on ROM type
`ifdef ROM3
  parameter VERSION = 6;  // Version 6 for ROM3 (1MB Apple IIgs)
`else
  parameter VERSION = 5;  // Version 5 for ROM1 (256K Apple IIgs)  
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
reg [15:0] cmd_timeout;  // Timeout counter for stuck commands
reg [63:0] cmd_data;
reg [3:0] initial_cmd_len;
reg cmd_response_ready;  // Flag indicating command completed with response
reg strobe_prev;  // Previous strobe value for edge detection
reg c024_was_read;  // Track if C024 was read on previous strobe (for falling edge handling)

// Device configuration registers
reg [7:0] adb_mode;
reg [7:0] kbd_ctl_addr = 8'd2;
reg [7:0] mouse_ctl_addr = 8'd3;
reg [7:0] repeat_rate, repeat_delay;
reg [7:0] char_set = 8'd0;
reg [7:0] layout = 8'd0;
reg [7:0] repeat_info = 8'h23;  // Key repeat configuration: delay[6:4], rate[3:0]

// Interrupt and status flags
reg data_int, mouse_int, kbd_int;
reg valid_mouse_data;
reg valid_kbd;
reg mouse_coord;
reg cmd_full;

// Device simulation - 16 possible devices, 4 registers each
reg [7:0] device_registers [15:0][3:0];  // [device][register]
reg [15:0] device_present;               // Bit mask of present devices
reg [7:0] device_data_pending [15:0];    // Pending data count per device

// Keyboard FIFO and management
parameter MAX_KBD_BUF = 8;
reg [7:0] kbd_fifo [MAX_KBD_BUF-1:0];    // Keyboard FIFO buffer
reg [3:0] kbd_fifo_head;                 // FIFO head pointer
reg [3:0] kbd_fifo_tail;                 // FIFO tail pointer  
reg [3:0] kbd_fifo_count;                // Number of keys in FIFO
reg kbd_strobe;                          // Keyboard strobe bit

// Modifier key tracking for selftest override and keyboard processing
reg shift_down;           // Bit 0: Shift key down
reg ctrl_down;            // Bit 1: Control key down
reg option_down;          // Bit 6: Option key down
reg cmd_down;             // Bit 7: Command key down
reg reset_key_down;       // Reset key (F11 mapped to 0x7F) is pressed

// Reset key output - active when Reset key is pressed
// The ROM checks for Ctrl+Reset to trigger reset
assign reset_key_pressed = reset_key_down;

// Key repeat state - GSplus-style approach (repeat on C000 read when strobe clear)
reg ps2_key_held;                    // A key is currently held down
reg [8:0] held_ps2_key;              // PS/2 scancode of held key
reg [7:0] held_iie_char;             // ASCII character for repeat
reg [15:0] repeat_vbl_target;        // VBL count when next repeat should occur
reg c010_processed_this_strobe;      // Prevent multiple C010 processing per bus cycle
reg prev_strobe;                     // For edge detection

// 60Hz timing for repeat
reg [17:0] clk_60hz_counter;
reg [15:0] hz60_count;
localparam CLK_60HZ_PERIOD = 18'd233333; // 14MHz / 60Hz

// Repeat timing configuration (in VBL counts at 60Hz)
reg [7:0] repeat_delay_vbl;          // Initial delay before repeat starts
reg [7:0] repeat_rate_vbl;           // Interval between repeats

// IRQ generation
wire data_irq = data_int & (pending_data > 0);
wire mouse_irq = mouse_int & valid_mouse_data;
wire kbd_irq = kbd_int & kbd_strobe;
assign irq = data_irq | mouse_irq | kbd_irq;

// ADB controller internal RAM using bram module
reg [7:0] ram_addr;
reg [7:0] ram_din;
wire [7:0] ram_dout;
reg ram_wen;

bram #(
    .width_a(8),
    .widthad_a(8)
) adb_ram (
    .clock_a(CLK_14M),
    .wren_a(ram_wen),
    .address_a(ram_addr),
    .data_a(ram_din),
    .q_a(ram_dout),
    .enable_a(1'b1),
    
    // Port B unused
    .clock_b(CLK_14M),
    .wren_b(1'b0),
    .address_b(8'h00),
    .data_b(8'h00),
    .q_b(),
    .enable_b(1'b0)
);

// Apple IIe compatibility registers
reg [7:0] c025;

// PS/2 input handling - track toggle bits for edge detection
reg ps2_key_toggle_prev, ps2_mouse_toggle_prev;

// Modifier key states (moved up above with other regs)
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
      9'h078: ps2_to_apple_key = 8'h7F;  // F11 -> Apple Reset key (was 0x67/F11)
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

// Key repeat timing calculation functions

function is_fast_repeat_key;
  input [7:0] key_code;  // Apple ADB key code
  begin
    // Fast repeat keys: arrows (0x3B-0x3E), space (0x31), delete (0x33)
    is_fast_repeat_key = (key_code == 8'h31) ||  // Space
                        (key_code == 8'h33) ||   // Delete  
                        (key_code >= 8'h3B && key_code <= 8'h3E); // Arrow keys
  end
endfunction

function is_repeatable_key;
  input [7:0] key_code;  // Apple ADB key code
  begin
    // Repeatable keys are ASCII keys (not modifiers)
    // Exclude modifier keys: Shift (0x38, 0x7B), Control (0x36), Command (0x37), Option (0x3A)
    is_repeatable_key = (key_code != 8'h36) &&  // Control
                       (key_code != 8'h37) &&   // Command
                       (key_code != 8'h38) &&   // Left Shift
                       (key_code != 8'h3A) &&   // Option
                       (key_code != 8'h7B) &&   // Right Shift
                       (key_code != 8'h7F);     // Invalid (removed 8'h00 check - A key is valid!)
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

// VBL-based timing conversion functions (matching GSplus exactly)
function [7:0] delay_to_vbl_count;
  input [2:0] delay_setting;  // ADB delay setting (0-7)
  begin
    // GSplus: if(tmp1 == 4) g_adb_repeat_delay = 0; else g_adb_repeat_delay = (tmp1 + 1) * 15;
    case (delay_setting)
      3'd0: delay_to_vbl_count = 8'd15;  // (0+1)*15 = 15 VBL
      3'd1: delay_to_vbl_count = 8'd30;  // (1+1)*15 = 30 VBL  
      3'd2: delay_to_vbl_count = 8'd45;  // (2+1)*15 = 45 VBL
      3'd3: delay_to_vbl_count = 8'd60;  // (3+1)*15 = 60 VBL
      3'd4: delay_to_vbl_count = 8'd0;   // No repeat (GSplus: tmp1 == 4)
      default: delay_to_vbl_count = 8'd45; // Default to 45 VBL for invalid values
    endcase
  end
endfunction

function [7:0] rate_to_vbl_count;
  input [3:0] rate_setting;    // ADB rate setting (0-9)
  input       fast_repeat;     // Fast repeat enabled for this key  
  reg [7:0] base_rate;
  reg [3:0] tmp1;
  begin
    // GSplus logic: if(g_rom_version >= 3) tmp1 = 9 - tmp1; (assume ROM3)
    tmp1 = 4'd9 - rate_setting;
    
    // GSplus rate conversion
    case (tmp1)
      4'd0: base_rate = 8'd1;    // GSplus: g_adb_repeat_rate = 1
      4'd1: base_rate = 8'd2;    // GSplus: g_adb_repeat_rate = 2  
      4'd2: base_rate = 8'd3;    // GSplus: g_adb_repeat_rate = 3
      4'd3: base_rate = 8'd3;    // GSplus: g_adb_repeat_rate = 3
      4'd4: base_rate = 8'd4;    // GSplus: g_adb_repeat_rate = 4
      4'd5: base_rate = 8'd5;    // GSplus: g_adb_repeat_rate = 5
      4'd6: base_rate = 8'd7;    // GSplus: g_adb_repeat_rate = 7
      4'd7: base_rate = 8'd15;   // GSplus: g_adb_repeat_rate = 15
      4'd8: base_rate = 8'd30;   // GSplus: g_adb_repeat_rate = 30 (ROM3)
      4'd9: base_rate = 8'd60;   // GSplus: g_adb_repeat_rate = 60 (ROM3)
      default: base_rate = 8'd3; // Default to 3 VBL
    endcase
    
    // Apply fast repeat (GSplus doesn't seem to implement this in the rates)
    // Keep simple for now - fast repeat handled elsewhere in GSplus
    rate_to_vbl_count = base_rate;
  end
endfunction

// Combinational output for same-cycle reads (bypasses registered dout)
// This is needed because the CPU reads data in the same cycle as the address is presented
reg [7:0] dout_comb_reg;
assign dout_comb = dout_comb_reg;

always @(*) begin
  // Default to registered dout
  dout_comb_reg = dout;

  // Override for specific addresses that need combinational response
  case (addr)
    8'h24: begin  // $C024 - Mouse Data
      if (rw) begin
        if (valid_mouse_data) begin
          if (mouse_coord)
            dout_comb_reg = device_registers[3][0];  // Y + button
          else
            dout_comb_reg = device_registers[3][1];  // X + always-1-bit
        end else begin
          // No new data - return appropriate "no movement" value
          if (mouse_coord)
            dout_comb_reg = {device_registers[3][0][7], 7'b0000000};  // Y: last button state, no delta
          else
            dout_comb_reg = 8'h80;  // X: bit7 always 1, no delta
        end
      end
    end
    8'h27: begin  // $C027 - ADB Status
      if (rw) begin
        dout_comb_reg = {
          valid_mouse_data | (pending_data > 0),  // bit 7: mouse data valid
          mouse_int,                               // bit 6: mouse interrupt enable
          pending_data > 0 ? 1'b1 : 1'b0,         // bit 5: data valid
          data_int,                                // bit 4: data interrupt enable
          valid_kbd,                               // bit 3: keyboard data valid
          kbd_int,                                 // bit 2: keyboard interrupt enable
          mouse_coord,                             // bit 1: mouse coordinate flag
          cmd_full                                 // bit 0: command full
        };
      end
    end
    8'h00: begin  // $C000 - Keyboard data
      if (rw) begin
        dout_comb_reg = K;
      end
    end
    default: begin
      // Use registered dout for other addresses
      dout_comb_reg = dout;
    end
  endcase
end

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
    cmd_timeout <= 16'd0;
    valid_mouse_data <= 1'b0;
    valid_kbd <= 1'b0;
    mouse_coord <= 1'b0;
    cmd_response_ready <= 1'b0;
    strobe_prev <= 1'b0;
    c024_was_read <= 1'b0;

    // Initialize command processing registers
    cmd <= 8'd0;
    cmd_len <= 4'd0;
    cmd_data <= 64'd0;
    initial_cmd_len <= 4'd0;

    // Initialize repeat timing registers
    repeat_rate <= 8'd0;
    repeat_delay <= 8'd0;

    // Initialize Apple IIe compatibility register
    c025 <= 8'd0;

    // Initialize output register
    dout <= 8'd0;

    // Initialize data register with ADB ready status (GSplus-style)
    // Set bit 3 (0x08) = SRQ flag to indicate ADB controller is ready
    data <= 32'h00000008;  // SRQ bit set, indicating ADB ready for keyboard operations
    
    // Initialize device addresses
    kbd_ctl_addr <= 8'd2;
    mouse_ctl_addr <= 8'd3;
    adb_mode <= 8'd0;
    repeat_info <= 8'h23;
    char_set <= 8'd0;
    layout <= 8'd0;
    
    // Initialize RAM control signals
    ram_wen <= 1'b0;
    ram_addr <= 8'h00;
    ram_din <= 8'h00;
    
    // PS/2 input tracking
    ps2_key_toggle_prev <= 1'b0;
    ps2_mouse_toggle_prev <= 1'b0;
    
    // Modifier key states
    shift_down <= 1'b0;
    ctrl_down <= 1'b0;
    cmd_down <= 1'b0;
    option_down <= 1'b0;
    caps_lock_state <= 1'b0;
    reset_key_down <= 1'b0;
    
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
    kbd_strobe <= 1'b0;
    
    // Initialize ADB devices
    device_present <= 16'b0000_0000_0000_1100;  // Devices 2 (kbd) and 3 (mouse) present
    for (int i = 0; i < 16; i++) begin
      device_data_pending[i] <= 8'h00;
      for (int j = 0; j < 4; j++) begin
        device_registers[i][j] <= 8'h00;
      end
    end
    
    // Set up keyboard device (address 2) default registers
    device_registers[2][0] <= 8'h00;  // Register 0: Key data
    device_registers[2][1] <= 8'h00;  // Register 1: LEDs (if any)
    device_registers[2][2] <= 8'h00;  // Register 2: Exceptional event data
    device_registers[2][3] <= 8'h02;  // Register 3: Device ID - keyboard handler ID
    
    // Set up mouse device (address 3) default registers  
    device_registers[3][0] <= 8'h00;  // Register 0: Mouse button/movement data
    device_registers[3][1] <= 8'h00;  // Register 1: Resolution/settings
    device_registers[3][2] <= 8'h00;  // Register 2: Class data
    device_registers[3][3] <= 8'h01;  // Register 3: Device ID - mouse handler ID
    
    // Initialize keyboard FIFO
    kbd_fifo_head <= 4'd0;
    kbd_fifo_tail <= 4'd0;
    kbd_fifo_count <= 4'd0;
    kbd_strobe <= 1'b0;
    for (int i = 0; i < MAX_KBD_BUF; i++) begin
      kbd_fifo[i] <= 8'h00;
    end

    // Initialize modifier key states
    shift_down <= 1'b0;
    ctrl_down <= 1'b0;
    option_down <= 1'b0;
    cmd_down <= 1'b0;
    reset_key_down <= 1'b0;
    
    // Initialize key repeat state
    ps2_key_held <= 1'b0;
    held_ps2_key <= 9'd0;
    held_iie_char <= 8'd0;
    repeat_vbl_target <= 16'd0;
    c010_processed_this_strobe <= 1'b0;
    prev_strobe <= 1'b0;

    // Initialize 60Hz timing
    clk_60hz_counter <= 18'd0;
    hz60_count <= 16'd0;
    repeat_delay_vbl <= 8'd45;              // Default: 45 VBL = 750ms @ 60Hz
    repeat_rate_vbl <= 8'd3;                // Default: 3 VBL = ~20 repeats/sec
  end else begin
    // Default RAM control signals (override when needed)
    ram_wen <= 1'b0;
    
    // Track PS/2 toggle bits for edge detection
    ps2_key_toggle_prev <= ps2_key[10];
    ps2_mouse_toggle_prev <= ps2_mouse[24];
    
    // Track strobe signal to detect transaction boundaries
    prev_strobe <= strobe;
    
    // Clear C010 processing flag when strobe goes low (end of bus transaction)
    if (prev_strobe && !strobe) begin
      c010_processed_this_strobe <= 1'b0;
    end
    
    // Generate 60Hz counter from 14MHz clock
    if (clk_60hz_counter >= CLK_60HZ_PERIOD - 1) begin
      clk_60hz_counter <= 18'd0;
      hz60_count <= hz60_count + 16'd1;  // Increment 60Hz counter
    end else begin
      clk_60hz_counter <= clk_60hz_counter + 18'd1;
    end
    
    // PS/2 keyboard event processing
    // MiSTer toggles bit 10 on every key press/release - if toggle changed, it's a valid new event
    if (ps2_key[10] != ps2_key_toggle_prev) begin
`ifdef SIMULATION
      $display("ADB: PS2 KEY EVENT: key=%03h down=%0d", ps2_key[8:0], ps2_key[9]);
`endif
      
      // Handle Caps Lock toggle
      if (ps2_key[8:0] == 9'h058 && ps2_key[9]) begin  // Caps Lock pressed
        caps_lock_state <= ~caps_lock_state;
        capslock <= ~caps_lock_state;
      end
      
      // Handle modifier keys (only when selftest override is not active)
      if (!selftest_override) begin
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
      end
      
      // Track F11 (PS/2 0x078) as the Apple Reset key
      // Reset key is special - it doesn't generate characters but signals reset intent
      if (ps2_key[8:0] == 9'h078) begin  // F11 -> Reset key
        reset_key_down <= ps2_key[9];  // Track press/release state
`ifdef DEBUG_ADB
        if (ps2_key[9]) begin
          $display("ADB: RESET KEY (F11) PRESSED - ctrl_down=%0d open_apple=%0d closed_apple=%0d", ctrl_down, open_apple, closed_apple);
        end else begin
          $display("ADB: RESET KEY (F11) RELEASED");
        end
`endif
      end

      // Process normal keys (not modifier keys or reset key)
      // Skip modifier keys: Shift (0x012, 0x059), Ctrl (0x014, 0x114), Alt (0x011, 0x111), Win/Menu (0x11f, 0x127)
      // Also skip F11 (0x078) which is now the reset key
      if (ps2_key[8:0] != 9'h012 && ps2_key[8:0] != 9'h059 &&  // Shift
          ps2_key[8:0] != 9'h014 && ps2_key[8:0] != 9'h114 &&  // Ctrl
          ps2_key[8:0] != 9'h011 && ps2_key[8:0] != 9'h111 &&  // Alt
          ps2_key[8:0] != 9'h11f && ps2_key[8:0] != 9'h127 &&  // Win/Menu
          ps2_key[8:0] != 9'h058 &&                             // Caps Lock
          ps2_key[8:0] != 9'h078) begin                         // F11 (Reset key)
        reg [7:0] temp_apple_key;
        reg [7:0] temp_iie_char;

        temp_apple_key = ps2_to_apple_key(ps2_key[8:0]);

        if (temp_apple_key != 8'h7F) begin
          if (ps2_key[9]) begin  // Key pressed (not released)
`ifdef SIMULATION
            $display("ADB: PS2 KEY DOWN: PS2=%03h Apple=%02h", ps2_key[8:0], temp_apple_key);
`endif
            temp_iie_char = adb_to_apple_iie_ascii(
              temp_apple_key[6:0],
              shift_down,
              ctrl_down,
              caps_lock_state
            );

            // Track this key as held down for potential repeat
            if (is_repeatable_key(temp_apple_key) && temp_iie_char != 8'hFF) begin
              ps2_key_held <= 1'b1;
              held_ps2_key <= ps2_key[8:0];  // Store PS/2 scancode
              held_iie_char <= temp_iie_char;   // Store ASCII for repeat

              // Set initial repeat timer (first repeat after delay)
              repeat_vbl_target <= hz60_count + {8'd0, repeat_delay_vbl};
            end

            // Add to keyboard FIFO if there's space
            if (kbd_fifo_count < MAX_KBD_BUF[3:0]) begin
              kbd_fifo[kbd_fifo_head[2:0]] <= temp_apple_key;
              kbd_fifo_head <= (kbd_fifo_head + 4'd1) & 4'd7;  // MAX_KBD_BUF-1 mask
              kbd_fifo_count <= kbd_fifo_count + 4'd1;

              valid_kbd <= 1'b1;
              device_data_pending[2] <= 8'h01;

              // Update Apple IIe K register immediately
              if (temp_iie_char != 8'hFF) begin
`ifdef DEBUG_ADB
                $display("ADB: Setting K register: PS2=%03h Apple=%02h ASCII=%02h", ps2_key[8:0], temp_apple_key, temp_iie_char);
`endif
                K <= {1'b1, temp_iie_char[6:0]};  // Set strobe bit + 7-bit ASCII
                akd <= 1'b1;  // Any key down
              end
            end
          end else begin
            // Key released
`ifdef SIMULATION
            $display("ADB: PS2 KEY UP: PS2=%03h (held=%03h held_flag=%0d)", ps2_key[8:0], held_ps2_key, ps2_key_held);
`endif
            // Stop repeat if this was the held PS/2 key
            if (ps2_key_held && (ps2_key[8:0] == held_ps2_key)) begin
              ps2_key_held <= 1'b0;
              held_ps2_key <= 9'd0;
              held_iie_char <= 8'd0;
              repeat_vbl_target <= 16'd0;
              c025[3] <= 1'b0;  // Clear repeat function flag
            end

            akd <= 1'b0;  // Clear any key down
          end
        end
      end
    end
    
    // Key repeat: disabled for now - was causing keyboard to hang
    // TODO: Implement proper repeat that doesn't flood FIFO
    // The issue is that repeat needs to be gated by whether the FIFO is being consumed,
    // not just blindly adding characters on a timer
    
    // PS/2 mouse event processing
    // PS/2 format: [7:0]=status (bit0=lbtn, bit1=rbtn, bit2=mbtn, bit3=1, bit4=Xsign, bit5=Ysign)
    //              [15:8]=X delta, [23:16]=Y delta, [24]=toggle
    // MiSTer only toggles bit 24 when there's meaningful data (movement or button change)
    if (ps2_mouse[24] != ps2_mouse_toggle_prev) begin
      // Build ADB mouse data format (2 bytes per Apple IIgs spec):
      // Byte 0: bit7=~button, bits6:0=Y delta (clamped to 7-bit signed, -63 to +63)
      // Byte 1: bit7=1, bits6:0=X delta (clamped to 7-bit signed, -63 to +63)

      // Clamp X delta from 8-bit signed to 7-bit signed range (-63 to +63)
      // ps2_mouse[15:8] is 8-bit signed X delta
      if ($signed(ps2_mouse[15:8]) > 63)
        device_registers[3][1] <= {1'b1, 7'd63};      // Clamp to +63
      else if ($signed(ps2_mouse[15:8]) < -63)
        device_registers[3][1] <= {1'b1, 7'b1000001}; // Clamp to -63 (0x41 in 7-bit signed)
      else
        device_registers[3][1] <= {1'b1, ps2_mouse[14:8]};

      // Clamp Y delta from 8-bit signed to 7-bit signed range (-63 to +63)
      // ps2_mouse[23:16] is 8-bit signed Y delta
      // Negate Y for Apple IIgs screen coordinates (positive Y = cursor moves down)
      // Note: Must negate the full 8-bit value, then take lower 7 bits for ADB format
      if ($signed(ps2_mouse[23:16]) > 63)
        device_registers[3][0] <= {~ps2_mouse[0], 7'b1000001}; // Clamp to -63 (negated)
      else if ($signed(ps2_mouse[23:16]) < -63)
        device_registers[3][0] <= {~ps2_mouse[0], 7'd63};      // Clamp to +63 (negated)
      else begin
        // Negate the 8-bit signed Y value, then extract lower 7 bits
        reg signed [7:0] neg_y;
        neg_y = -$signed(ps2_mouse[23:16]);
        device_registers[3][0] <= {~ps2_mouse[0], neg_y[6:0]};
      end

      valid_mouse_data <= 1'b1;
      device_data_pending[3] <= 8'h02;  // 2 bytes available

`ifdef DEBUG_ADB
      $display("ADB MOUSE: X=%d Y=%d btn=%d -> reg0=0x%02h reg1=0x%02h",
               $signed(ps2_mouse[15:8]), $signed(ps2_mouse[23:16]), ps2_mouse[0],
               {~ps2_mouse[0], ps2_mouse[22:16]}, {1'b1, ps2_mouse[14:8]});
`endif
    end
    
    // Timeout handling for stuck commands
    if (state == CMD) begin
      cmd_timeout <= cmd_timeout + 16'd1;
      if (cmd_timeout >= 16'd32000) begin  // ~2ms timeout at 14MHz
        state <= IDLE;
        cmd_full <= 1'b0;
        cmd_timeout <= 16'd0;
      end
    end else begin
      cmd_timeout <= 16'd0;
    end
    
    // Self-test override: simulate Command+Option+Control pressed
    // This must be outside PS/2 processing to work continuously
    if (selftest_override) begin
      cmd_down <= 1'b1;
      option_down <= 1'b1;
      ctrl_down <= 1'b1;
      
      // Also set Apple IIe compatibility flags
      open_apple <= 1'b1;     // Command key maps to open apple
      closed_apple <= 1'b1;   // Option key maps to closed apple  
      apple_ctrl <= 1'b1;     // Control key
    end
    
    // Key repeat moved back to $C000 reads - no background repeat generation

    // CMD state machine: Execute command when all bytes have been received
    // This runs every cycle, independent of strobe, to execute commands after the last byte is stored
    // NOTE: Only READ_MEM (0x09) needs this - other commands are handled in the strobe-gated block
    if (state == CMD && cmd_len == 4'd0 && cmd == 8'h09) begin
`ifdef DEBUG_ADB
      $display("ADB CMD EXEC: cmd=0x%02h cmd_data=%016x", cmd, cmd_data);
`endif
      state <= IDLE;
      cmd_response_ready <= 1'b1;  // Signal that command has been processed

      case (cmd)
        8'h09: begin
          // READ_MEM - Read byte from ADB controller memory (2 bytes)
          // cmd_data[15:8] = address LOW byte (first byte sent)
          // cmd_data[7:0] = address HIGH byte (second byte sent)
          // Full 16-bit address = (cmd_data[7:0] << 8) | cmd_data[15:8]

`ifdef DEBUG_ADB
          $display("ADB READ_MEM: addr=0x%04h (bytes: low=0x%02h high=0x%02h)", {cmd_data[7:0], cmd_data[15:8]}, cmd_data[15:8], cmd_data[7:0]);
`endif

          if ({cmd_data[7:0], cmd_data[15:8]} < 16'h0100) begin
            // RAM area (0x00-0xFF): Read from RAM
            ram_addr <= cmd_data[15:8];  // Only low byte matters for RAM
            ram_wen <= 1'b0;

            // Special handling for specific addresses (from gsplus)
            case (cmd_data[15:8])
              8'h01: begin
                // ROM checksum low byte
                data <= { 24'd0, 8'h72 };
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: Special addr 0x01 -> 0x72 (ROM checksum low)");
`endif
              end
              8'h03: begin
                // ROM checksum high byte - ROM1=0xF7, ROM3=0x26
                if (VERSION >= 6) begin
                  data <= { 24'd0, 8'h26 };
`ifdef DEBUG_ADB
                  $display("ADB READ_MEM: Special addr 0x03 -> 0x26 (ROM checksum high ROM3)");
`endif
                end else begin
                  data <= { 24'd0, 8'hF7 };
`ifdef DEBUG_ADB
                  $display("ADB READ_MEM: Special addr 0x03 -> 0xF7 (ROM checksum high ROM1)");
`endif
                end
              end
              8'h0B: begin
                // Special key state byte for Out of This World (ROM 1)
                data <= { 24'd0, 8'h00 };
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: Special addr 0x0B -> 0x00");
`endif
              end
              8'h0C: begin
                // Special key state byte for Out of This World (ROM 3)
                data <= { 24'd0, 8'h00 };
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: Special addr 0x0C -> 0x00");
`endif
              end
              8'hE2: begin
                // No Apple IIe keyboard support (bits 1 and 2 = 1)
                data <= { 24'd0, 8'h06 };
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: Special addr 0xE2 -> 0x06 (no IIe keyboard)");
`endif
              end
              8'hE8: begin
                // Apple/Option key state
                data <= { 24'd0, 8'h00 };
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: Special addr 0xE8 -> 0x00 (no Apple/Option keys)");
`endif
              end
              default: begin
                // Normal RAM read
                data <= { 24'd0, ram_dout };
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: RAM addr=0x%02h data=0x%02h", cmd_data[15:8], ram_dout);
`endif
              end
            endcase
          end else if ({cmd_data[7:0], cmd_data[15:8]} >= 16'h1000 && {cmd_data[7:0], cmd_data[15:8]} < 16'h2000) begin
            // ROM area (0x1000-0x1FFF): ROM self-test checksum
            case ({cmd_data[7:0], cmd_data[15:8]})
              16'h1400: begin
                data <= { 24'd0, 8'h72 };  // ROM checksum low byte
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: ROM addr 0x1400 -> 0x72 (checksum low)");
`endif
              end
              16'h1401: begin
                // ROM checksum high byte - ROM1=0xF7, ROM3=0x26
                if (VERSION >= 6) begin
                  data <= { 24'd0, 8'h26 };
`ifdef DEBUG_ADB
                  $display("ADB READ_MEM: ROM addr 0x1401 -> 0x26 (checksum high ROM3)");
`endif
                end else begin
                  data <= { 24'd0, 8'hF7 };
`ifdef DEBUG_ADB
                  $display("ADB READ_MEM: ROM addr 0x1401 -> 0xF7 (checksum high ROM1)");
`endif
                end
              end
              default: begin
                data <= { 24'd0, 8'h00 };  // Rest of ROM returns 0
`ifdef DEBUG_ADB
                $display("ADB READ_MEM: ROM addr 0x%04h -> 0x00", {cmd_data[7:0], cmd_data[15:8]});
`endif
              end
            endcase
          end else begin
            // Out of range
            data <= { 24'd0, 8'h00 };
`ifdef DEBUG_ADB
            $display("ADB READ_MEM: addr 0x%04h out of range -> 0x00", {cmd_data[7:0], cmd_data[15:8]});
`endif
          end
          pending_data <= 3'd1;
        end
        // Add other commands that need execution here if needed in future
        default: begin
          // Unknown command or already handled inline
`ifdef DEBUG_ADB
          $display("ADB CMD EXEC: cmd=0x%02h not handled in exec block (may be handled inline)", cmd);
`endif
        end
      endcase
    end

    // Address decoding and register access
    if (strobe) begin
`ifdef DEBUG_ADB
      $display("ADB MODULE: strobe=1, addr=0x%02h (%d), rw=%b", addr, addr, rw);
`endif
    end
    case (addr)

      8'h25: begin  // $C025 - Modifier Key Register
        if (rw) begin
          // Return actual modifier key states, not stored c025 value
          // Bit 7: Command key down (open apple)
          // Bit 6: Option key down (closed apple)
          // Bit 5: Updated modifier key latch (not implemented)
          // Bit 4: Numeric keypad key down (not implemented)
          // Bit 3: Repeat function active
          // Bit 2: Caps Lock active
          // Bit 1: Control key down
          // Bit 0: Shift key down
          dout <= {cmd_down, option_down, 1'b0, 1'b0, c025[3], caps_lock_state, ctrl_down, shift_down};
        end else if (cen & strobe) begin
          c025 <= din;
        end
      end

      8'h26: begin
`ifdef DEBUG_ADB
        $display("DEBUG: ADB 26 case entered, rw=%b cen=%b strobe=%b", rw, cen, strobe);
`endif
        // Read $C026 - ADB Command/Data Register
        if (rw) begin
          case (state)
            IDLE: begin
              // Build response byte per documentation (Table 6-3):
              // Bit 7: Response received (set when command completes)
              // Bit 6: Abort/error
              // Bit 5: Reset key sequence
              // Bit 4: Buffer flush key sequence
              // Bit 3: SRQ (keyboard ready)
              // Bits 2-0: Number of data bytes to return (count - 1, or 0 if no data)
              if (cmd_response_ready) begin
                // Command completed - return response with bit 7 set
                // Format: bit 7=response, bit 6=0, bits 5-4=0, bit 3=SRQ, bits 2-0=data count
                if (pending_data > 3'd0) begin
                  dout <= 8'h80 | {5'd0, pending_data - 3'd1};  // Response + data count
`ifdef DEBUG_ADB
                  $display("ADB READ C026: cmd_response_ready=1, pending_data=%d, returning 0x%02h", pending_data, 8'h80 | {5'd0, pending_data - 3'd1});
`endif
                end else begin
                  dout <= 8'h80;  // Response received, no data
`ifdef DEBUG_ADB
                  $display("ADB READ C026: cmd_response_ready=1, pending_data=0, returning 0x80");
`endif
                end
              end else begin
                // No command response - return SRQ/status only
                dout <= data[7:0];  // data[7:0] contains SRQ status (0x08)
                if (pending_irq) dout <= 8'b0001_0000;
                //$display("ADB READ C026: cmd_response_ready=0, data[7:0]=0x%02h, returning 0x%02h", data[7:0], pending_irq ? 8'b0001_0000 : data[7:0]);
              end
            end
            CMD: begin
              // Return status indicating ready for command bytes
              // Return 0x80 to indicate "ready" (similar to command response status)
              dout <= 8'h80;
`ifdef DEBUG_ADB
              $display("ADB C026 READ in CMD state: returning 0x80 (ready for cmd data), cmd_len=%d", cmd_len);
`endif
            end
            DATA: begin
              dout <= data[7:0];
`ifdef DEBUG_ADB
              $display("ADB C026 READ in DATA state: returning data[7:0]=0x%02h, pending_data=%d", data[7:0], pending_data);
`endif
              // Shift data and decrement counter on each read
              data <= { 8'd0, data[31:8] };
              if (pending_data > 3'd0) pending_data <= pending_data - 3'd1;
              if (pending_data == 3'd1) state <= IDLE;
`ifdef DEBUG_ADB
              $display("ADB C026 DATA: After read, pending_data will be %d, state will be %d", pending_data - 3'd1, (pending_data == 3'd1) ? 0 : 2);
`endif
            end
          endcase
          // Clear response flag after read when no pending data
          // Use strobe FALLING edge to transition after the status byte read completes
          if (~strobe & strobe_prev & (state == IDLE) & cmd_response_ready & (pending_data == 3'd0)) begin
            cmd_response_ready <= 1'b0;
          end
          // Transition to DATA state if there's pending data
          // Use strobe FALLING edge so the transition happens AFTER status byte is returned
          // This allows the ROM to read the status byte (0x80), then do a SECOND read for the data
          if (~strobe & strobe_prev & (state == IDLE) & cmd_response_ready & (pending_data > 3'd0)) begin
            cmd_response_ready <= 1'b0;
            state <= DATA;
`ifdef DEBUG_ADB
            $display("ADB C026 READ: Transitioning IDLE->DATA on strobe falling edge, pending_data=%d, data=%08x data[7:0]=0x%02h", pending_data, data, data[7:0]);
`endif
          end
        end
        // Write $C026 - ADB Commands
        else if (strobe & ~strobe_prev) begin  // Edge detect: only process on rising edge of strobe
`ifdef DEBUG_ADB
          $display("ADB_MODULE_WR_C026: cen=%b strobe=%b din=%02h [PROCESSING]", cen, strobe, din);
`endif
          case (state)

            IDLE: begin
`ifdef DEBUG_ADB
              $display("ADB PROCESSING WRITE in IDLE state");
              $display("ADB WRITE C026 IDLE: din=0x%02h, prev_cmd=0x%02h, state=%d, cmd_len=%d", din, cmd, state, cmd_len);
`endif
              cmd <= din;
              cmd_timeout <= 16'd0;  // Reset timeout for new command
              cmd_data <= 64'd0;     // Clear command data buffer
              initial_cmd_len <= 4'd0; // Clear initial length
              case (din)
                8'h01: begin
                  // ABORT - Clear all ADB state including key repeat
                  ps2_key_held <= 1'b0;
                  repeat_vbl_target <= 16'd0;
                end
                8'h03: begin
                  // FLUSH keyboard buffer - also stop key repeat
                  ps2_key_held <= 1'b0;
                  repeat_vbl_target <= 16'd0;

                  // Clear keyboard FIFO
                  kbd_fifo_head <= 4'd0;
                  kbd_fifo_tail <= 4'd0;
                  kbd_fifo_count <= 4'd0;
                  kbd_strobe <= 1'b0;
                  valid_kbd <= 1'b0;
                end
                8'h04: begin cmd_len <= 4'd1; initial_cmd_len <= 4'd1; state <= CMD; end
                8'h05: begin cmd_len <= 4'd1; initial_cmd_len <= 4'd1; state <= CMD; end
                8'h06: begin cmd_len <= 4'd3; initial_cmd_len <= 4'd3; state <= CMD; end
                8'h07: begin
                  // SYNC command - length depends on ROM version
                  // ROM1 (VERSION=5): 4 bytes, ROM3 (VERSION=6): 8 bytes
                  // KEGS: g_rom_version == 1 means ROM01, which maps to our VERSION < 6
                  cmd_len <= (VERSION < 6) ? 4'd4 : 4'd8;
                  initial_cmd_len <= (VERSION < 6) ? 4'd4 : 4'd8;
                  state <= CMD;
                end
                8'h08: begin
                  cmd_len <= 4'd2; initial_cmd_len <= 4'd2; state <= CMD;
`ifdef DEBUG_ADB
                  $display("ADB CMD 0x08: Transitioning to CMD state, cmd_len=2");
`endif
                end
                8'h09: begin
                  cmd_len <= 4'd2; initial_cmd_len <= 4'd2; state <= CMD;
`ifdef DEBUG_ADB
                  $display("ADB CMD 0x09 (READ_MEM): Transitioning to CMD state, cmd_len=2");
`endif
                end
                8'h0a: begin
                  // Read ADB modes
                  data <= { 24'd0, adb_mode };
                  pending_data <= 3'd1;
                end
                8'h0b: begin
                  // Read device info - returns config including repeat_info
                  data <= {
                    {mouse_ctl_addr[3:0], kbd_ctl_addr[3:0]},  // Combined addr byte
                    repeat_info,   // Key repeat settings
                    char_set,
                    layout
                  };
                  pending_data <= 3'd4;
                end
                8'h0d: begin
                  // ADB Version command - return version number
                  data <= {24'd0, VERSION[7:0]};  // Clear upper bits, set version in LSB
                  pending_data <= 3'd1;
                  state <= IDLE;  // Immediate response, return to IDLE
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
                8'h11: begin cmd_len <= 4'd1; initial_cmd_len <= 4'd1; state <= CMD; end
                8'h12: begin
                  if (VERSION >= 6) begin
                    cmd_len <= 4'd2; initial_cmd_len <= 4'd2; state <= CMD;
                  end else begin
                    // ROM1 doesn't support command 0x12, return to IDLE
                    state <= IDLE;
                  end
                end
                8'h13: begin
                  if (VERSION >= 6) begin
                    cmd_len <= 4'd2; initial_cmd_len <= 4'd2; state <= CMD;
                  end else begin
                    // ROM1 doesn't support command 0x13, return to IDLE
                    state <= IDLE;
                  end
                end
                8'h73: ; // disable SRQ on mouse
                default: begin
`ifdef DEBUG_ADB
                  $display("ADB WRITE C026 DEFAULT: din=0x%02h, cmd=0x%02h, din>=0x10=%d, din[1:0]=%b, state=%d", din, cmd, (din >= 8'h10), din[1:0], state);
`endif
                  // Check if this is a device command (pattern: AAAARRCCT)
                  // A=address, R=register, C=command, T=type
                  if (din >= 8'h10) begin  // Device commands start at 0x10
`ifdef DEBUG_ADB
                    $display("ADB DEVICE COMMAND: din=0x%02h, device=%d, cmd=%b", din, din[7:4], din[1:0]);
`endif
                    // Decode device command: AAAARRCCT (A=addr, R=reg, C=cmd bits)
                    case (din[1:0])  // dev_cmd bits
                      2'b01: begin // FLUSH device
                        cmd_response_ready <= 1'b1;  // Set response flag
                        pending_data <= 3'd0;        // No data bytes
                        state <= IDLE;
`ifdef DEBUG_ADB
                        $display("ADB FLUSH device %d: setting cmd_response_ready=1, pending_data=0", din[7:4]);
`endif
                      end
                      2'b10: begin // LISTEN (write to device)
                        if (device_present[din[7:4]]) begin
                          cmd_len <= 4'd2;  // Expect 2 data bytes for LISTEN
                          initial_cmd_len <= 4'd2;
                          state <= CMD;
                        end else begin
                          cmd_response_ready <= 1'b1;  // Set response flag even for non-existent device
                          pending_data <= 3'd0;        // No data bytes
                          state <= IDLE;
                        end
                      end
                      2'b11: begin // TALK (read from device)
                        if (device_present[din[7:4]]) begin
                          // Check for special multi-byte responses
                          if (din[7:4] == 4'd2 && din[3:2] == 2'd3) begin
                            // Keyboard device register 3 - return device handler ID (2 bytes)
                            data <= { 16'd0, 8'h02, 8'h07 };  // Handler ID=$02, some additional info
                            pending_data <= 3'd2;
                          end else if (din[7:4] == 4'd3 && din[3:2] == 2'd3) begin
                            // Mouse device register 3 - return device handler ID (2 bytes)
                            data <= { 16'd0, 8'h01, 8'h63 };  // Handler ID=$01, mouse info
                            pending_data <= 3'd2;
                          end else if (din[7:4] == 4'd2 && din[3:2] == 2'd0) begin
                            // Keyboard device register 0 - return key data if available
                            if (device_data_pending[2] > 0) begin
                              data <= { 24'd0, device_registers[2][0] };
                              pending_data <= 3'd1;
                              device_data_pending[2] <= 8'h00;  // Clear pending data
                              if ((device_registers[2][0] & 8'h80) != 8'd0) valid_kbd <= 1'b0;  // Clear on key release
                            end else begin
                              data <= 32'd0;  // No data available
                              pending_data <= 3'd0;
                            end
                          end else if (din[7:4] == 4'd3 && din[3:2] == 2'd0) begin
                            // Mouse device register 0 - return mouse data if available
                            // ADB mouse returns 2 bytes: reg0 (Y+button) and reg1 (X)
                            if (device_data_pending[3] > 0) begin
                              data <= { 16'd0, device_registers[3][1], device_registers[3][0] };
                              pending_data <= 3'd2;  // 2 bytes of mouse data
                              device_data_pending[3] <= 8'h00;  // Clear pending data
                              valid_mouse_data <= 1'b0;  // Clear flag after reading
`ifdef DEBUG_ADB
                              $display("ADB MOUSE READ: returning 0x%02h 0x%02h",
                                       device_registers[3][0], device_registers[3][1]);
`endif
                            end else begin
                              data <= 32'd0;  // No data available
                              pending_data <= 3'd0;
                            end
                          end else begin
                            // Return single byte device register data
                            data <= { 24'd0, device_registers[din[7:4]][din[3:2]] };
                            pending_data <= 3'd1;
                          end
                          cmd_response_ready <= 1'b1;  // Set response flag
                          state <= IDLE;
                        end else begin
                          // Device not present - do NOT send response (per KEGS)
                          // KEGS doesn't call adb_response_packet for non-present devices
                          // This allows the ROM to poll multiple devices and only get
                          // responses from devices that actually exist
                          state <= IDLE;
`ifdef DEBUG_ADB
                          $display("ADB TALK device %d (NOT PRESENT): no response sent", din[7:4]);
`endif
                        end
                      end
                      default: begin
                        state <= IDLE;
                      end
                    endcase
                  end else begin
                    // Non-device command - unknown
                    state <= IDLE;
                  end
                end
              endcase
            end

            CMD: begin
`ifdef DEBUG_ADB
              $display("ADB CMD state: din=0x%02h cmd=0x%02h cmd_len=%d initial_cmd_len=%d", din, cmd, cmd_len, initial_cmd_len);
`endif

              // First,store incoming data byte and decrement counter (if cmd_len > 0)
              // This must happen BEFORE we try to execute any command
              if (cmd_len > 4'd0) begin
                // Store incoming data byte based on position
                case (initial_cmd_len)
                    4'd1: cmd_data[7:0] <= din;
                    4'd2: if (cmd_len == 2) cmd_data[15:8] <= din; else cmd_data[7:0] <= din;
                    4'd3: if (cmd_len == 3) cmd_data[23:16] <= din; else if (cmd_len == 2) cmd_data[15:8] <= din; else cmd_data[7:0] <= din;
                    4'd4: if (cmd_len == 4) cmd_data[31:24] <= din; else if (cmd_len == 3) cmd_data[23:16] <= din; else if (cmd_len == 2) cmd_data[15:8] <= din; else cmd_data[7:0] <= din;
                    4'd8:
                        case(cmd_len)
                            4'd8: cmd_data[63:56] <= din;
                            4'd7: cmd_data[55:48] <= din;
                            4'd6: cmd_data[47:40] <= din;
                            4'd5: cmd_data[39:32] <= din;
                            4'd4: cmd_data[31:24] <= din;
                            4'd3: cmd_data[23:16] <= din;
                            4'd2: cmd_data[15:8] <= din;
                            4'd1: cmd_data[7:0] <= din;
                        endcase
                    default: ; // Should not happen
                endcase

                // Decrement counter
                cmd_len <= cmd_len - 4'd1;

                // If this was the last byte (cmd_len==1), we'll execute the command next cycle
                if (cmd_len == 4'd1) begin
`ifdef DEBUG_ADB
                  $display("ADB CMD: Stored final byte din=0x%02h, will execute next cycle", din);
`endif
                end
              end
              // If cmd_len is 0, this means we stored all bytes last cycle
              // Now execute the completed command
              else begin
`ifdef DEBUG_ADB
                $display("ADB CMD COMPLETE: cmd=0x%02h cmd_data=%016x", cmd, cmd_data);
`endif
                state <= IDLE;
                cmd <= 8'h00;  // Clear cmd for next command

                case (cmd)
                  8'h04: adb_mode <= din | adb_mode;
                  8'h05: adb_mode <= adb_mode & ~din;
                  8'h06: begin
                    // SET_CONFIG (0x06) - Configure ADB parameters (3 bytes)
                    // Byte 2: mouse_ctl_addr, kbd_ctl_addr
                    // Byte 1: (reserved)
                    // Byte 0: repeat_info
                    mouse_ctl_addr <= {4'd0, cmd_data[23:20]};
                    kbd_ctl_addr   <= {4'd0, cmd_data[19:16]};
                    repeat_info    <= cmd_data[7:0];

                    // Recalculate VBL timing values immediately
                    repeat_delay_vbl <= delay_to_vbl_count(cmd_data[6:4]);
                    repeat_rate_vbl <= rate_to_vbl_count(cmd_data[3:0], 1'b0);
                  end
                  8'h07: begin
                    // SYNC (0x07) - Multi-byte command, process all data at once
                    if (initial_cmd_len == 4'd4) begin // ROM1
                      adb_mode       <= cmd_data[31:24];
                      mouse_ctl_addr <= {4'd0, cmd_data[23:20]};
                      kbd_ctl_addr   <= {4'd0, cmd_data[19:16]};
                      repeat_info    <= cmd_data[7:0];

                      // Recalculate VBL timing values
                      repeat_delay_vbl <= delay_to_vbl_count(cmd_data[6:4]);
                      repeat_rate_vbl <= rate_to_vbl_count(cmd_data[3:0], (cmd_data[31:24] & 8'h08) != 8'h00);
                    end else begin // ROM3 (8 bytes)
                      adb_mode       <= cmd_data[63:56];
                      mouse_ctl_addr <= {4'd0, cmd_data[55:52]};
                      kbd_ctl_addr   <= {4'd0, cmd_data[51:48]};
                      repeat_info    <= cmd_data[39:32];
                      char_set       <= cmd_data[23:16];
                      layout         <= cmd_data[15:8];

                      // Recalculate VBL timing values
                      repeat_delay_vbl <= delay_to_vbl_count(cmd_data[38:36]);
                      repeat_rate_vbl <= rate_to_vbl_count(cmd_data[35:32], (cmd_data[63:56] & 8'h08) != 8'h00);
                    end
                  end
                  8'h08: begin
                    // WRITE_MEM - Write byte to ADB controller memory (2 bytes)
                    // cmd_data[15:8] = address (single byte, 0-255)
                    // din = value to write
                    // Based on gsplus: only addresses < 0x100 are writable (RAM)
`ifdef DEBUG_ADB
                    $display("ADB WRITE_MEM: addr=0x%02h value=0x%02h", cmd_data[15:8], din);
`endif
                    if (cmd_data[15:8] < 8'h60) begin  // Only first 96 bytes are actual RAM
                      ram_addr <= cmd_data[15:8];
                      ram_din <= din;
                      ram_wen <= 1'b1;
                    end else begin
`ifdef DEBUG_ADB
                      $display("ADB WRITE_MEM: addr 0x%02h out of range, ignoring", cmd_data[15:8]);
`endif
                    end
                  end
                  8'h09: begin
                    // READ_MEM - Handled in CMD state execution block (runs when cmd_len==0)
                    // This is just a placeholder to show the command exists
                  end
                  8'h11: ; // send keycode data
                  8'h12: ; // cmd 12 - ROM3 only
                  8'h13: ; // cmd 13 - ROM3 only
                  default: begin
                    // Check if this is a device LISTEN command that needs data
                    if (cmd >= 8'h10) begin
                      if (cmd[1:0] == 2'b10) begin // LISTEN command
                        if (device_present[cmd[7:4]]) begin
                          // Store data in device register (Byte 1 is data, Byte 0 is unused)
                          device_registers[cmd[7:4]][cmd[3:2]] <= cmd_data[15:8];
                        end
                      end
                    end
                  end
                endcase
              end
            end
          endcase
        end else if (strobe) begin
`ifdef DEBUG_ADB
          $display("ADB_MODULE_WR_C026: cen=%b strobe=%b din=%02h [BLOCKED - CEN NOT HIGH]", cen, strobe, din);
`endif
        end
      end

      8'h27: begin
        // $C027 - ADB Control Register
        if (rw) begin
          // Read $C027 - Status bits
          // bit 7: Mouse Data register full (valid_mouse_data) OR command response ready
          // bit 6: Mouse interrupt enable
          // bit 5: Data register contains valid data (pending_data)
          // bit 4: Data interrupt enable
          // bit 3: Keyboard data valid
          // bit 2: Keyboard interrupt enable
          // bit 1: Mouse coordinate flag (0=X next, 1=Y next)
          // bit 0: Command full
          dout <= {
            valid_mouse_data | (pending_data > 0),  // bit 7: mouse data OR command response
            mouse_int,             // bit 6: mouse interrupt enable
            pending_data > 0 ? 1'b1 : 1'b0,  // bit 5: Command/Data register contains valid data
            data_int,              // bit 4: data interrupt enable
            valid_kbd,             // bit 3: keyboard data valid
            kbd_int,               // bit 2: keyboard interrupt enable
            mouse_coord,           // bit 1: mouse coordinate flag
            cmd_full               // bit 0: command full
          };
`ifdef DEBUG_ADB
          if (strobe && valid_mouse_data) begin
            $display("C027 READ: mouse_valid=1 mouse_coord=%b -> 0x%02h",
                     mouse_coord,
                     {valid_mouse_data | (pending_data > 0), mouse_int, pending_data > 0 ? 1'b1 : 1'b0, data_int, valid_kbd, kbd_int, mouse_coord, cmd_full});
          end
`endif
        end else if (cen & strobe) begin
          // Write $C027 - Interrupt enables
          mouse_int <= din[6];
          data_int <= din[4];
          kbd_int <= din[2];
        end
      end

      // Apple IIe keyboard compatibility registers
      8'h00: begin  // $C000 - Keyboard data
        if (rw) begin
          dout <= K;  // Return current key with strobe bit

          // GSplus-style key repeat: generate repeat on $C000 READ
          // Only trigger on RISING edge of strobe to prevent multiple repeats per bus cycle
          if (strobe && !strobe_prev && !K[7] && ps2_key_held && held_iie_char != 8'hFF && repeat_delay_vbl != 8'd0) begin
            if ($signed(hz60_count - repeat_vbl_target) >= 0) begin
              K <= {1'b1, held_iie_char[6:0]};
              c025[3] <= 1'b1;
              repeat_vbl_target <= hz60_count + {8'd0, repeat_rate_vbl};
`ifdef SIMULATION
              $display("ADB REPEAT: char=%02h at hz60=%d next_target=%d", held_iie_char, hz60_count, hz60_count + {8'd0, repeat_rate_vbl});
`endif
            end
          end
        end
      end
      
      8'h10: begin  // $C010 - Keyboard strobe clear (ANY access clears strobe)
        if (rw) begin
          dout <= K;  // Return K value on read
        end
        // Clear strobe on ANY access (read or write) - matches GSplus behavior
        if (cen & strobe & !c010_processed_this_strobe) begin
`ifdef DEBUG_ADB
          $display("ADB C010 WRITE PROCESSED (cen=%b, strobe=%b) - processing C010 clear", cen, strobe);
          $display("ADB C010: K before clear = %02h, fifo_count=%d", K, kbd_fifo_count);
`endif
          c010_processed_this_strobe <= 1'b1;  // Mark that we processed C010 this strobe transaction
          K <= {1'b0, K[6:0]};  // Clear strobe bit
          kbd_strobe <= 1'b0;  // Clear ADB strobe
          c025[3] <= 1'b0;  // Clear repeat function flag (GSplus: g_c025_val &= ~0x08)

          // Advance FIFO to next character
          if (kbd_fifo_count > 0) begin
            kbd_fifo_tail <= (kbd_fifo_tail + 1) % MAX_KBD_BUF;
            kbd_fifo_count <= kbd_fifo_count - 1;

            // Load next character if available (kbd_fifo_count > 1 means there's another after this one)
            if (kbd_fifo_count > 1) begin
              // Convert next FIFO entry to Apple IIe ASCII
              reg [7:0] next_char;
              next_char = adb_to_apple_iie_ascii(
                kbd_fifo[(kbd_fifo_tail + 1) % MAX_KBD_BUF][6:0],
                shift_down, ctrl_down, caps_lock_state
              );

              // Load next character - duplicates are allowed (e.g., "tt")
              K <= {1'b1, next_char[6:0]};
              kbd_strobe <= 1'b1;
`ifdef DEBUG_ADB
              $display("ADB C010: Loaded next FIFO char=%02h", next_char);
`endif
            end
          end
        end else if (cen & strobe & c010_processed_this_strobe) begin
`ifdef DEBUG_ADB
          $display("ADB C010 WRITE REJECTED - already processed this strobe transaction (cen=%b, strobe=%b)", cen, strobe);
`endif
        end
      end
      
      // Paddle/Joystick registers (stub)
      8'h60, 8'h61, 8'h62, 8'h63: begin
        dout <= 8'd0;
      end

      8'h64, 8'h65, 8'h66, 8'h67: begin
        dout <= 8'd0;
      end

      8'h24: begin
        // $C024 - Mouse Data Register (read-only)
        // Returns X delta then Y delta on alternating reads
        // Format: bit 7 = button state (inverted) for Y, always 1 for X
        //         bits 6:0 = signed delta value (-63 to +63)
        if (rw) begin
          // Combinational read output (no strobe needed)
          if (valid_mouse_data) begin
            if (mouse_coord) begin
              dout <= device_registers[3][0];  // Y + button
            end else begin
              dout <= device_registers[3][1];  // X + always-1-bit
            end
          end else begin
            // No new mouse data - return appropriate "no movement" value
            if (mouse_coord) begin
              // Y byte: last known button state, no delta
              dout <= {device_registers[3][0][7], 7'b0000000};
            end else begin
              // X byte: bit7 always 1, no delta
              dout <= 8'h80;
            end
          end

          // Mark that C024 was read this strobe cycle (for falling edge handling)
          if (strobe) begin
            c024_was_read <= 1'b1;
          end
        end
      end

      default: dout <= 8'd0;
    endcase

    // Handle C024 mouse_coord toggle on falling edge of strobe
    // This must be outside the case block because by the time strobe falls,
    // the address may have already changed to something else
    if (~strobe & strobe_prev & c024_was_read) begin
      if (valid_mouse_data) begin
        if (mouse_coord) begin
          // After reading Y, clear valid flag and reset coord
          valid_mouse_data <= 1'b0;
          mouse_coord <= 1'b0;
`ifdef DEBUG_ADB
          $display("C024 READ Y: 0x%02h (btn=%d, dy=%d)",
                   device_registers[3][0], ~device_registers[3][0][7],
                   $signed({device_registers[3][0][6], device_registers[3][0][6:0]}));
`endif
        end else begin
          // After reading X, toggle coord for next Y read
          mouse_coord <= 1'b1;
`ifdef DEBUG_ADB
          $display("C024 READ X: 0x%02h (dx=%d)",
                   device_registers[3][1],
                   $signed({device_registers[3][1][6], device_registers[3][1][6:0]}));
`endif
        end
      end else begin
        // Toggle coord even when no data (maintains alternating pattern)
        mouse_coord <= ~mouse_coord;
      end
      c024_was_read <= 1'b0;  // Clear the flag after handling
    end

    // Clear c024_was_read on falling edge even if it wasn't set (belt and suspenders)
    if (~strobe & strobe_prev) begin
      c024_was_read <= 1'b0;
    end

    // Update edge detection register on every cycle
    strobe_prev <= strobe;

`ifdef DEBUG_ADB
    // Debug: Track state changes
    if (state != 2'b00 || (strobe & ~strobe_prev)) begin
      $display("ADB_STATE_TRACK: state=%d strobe=%b strobe_prev=%b cmd_len=%d", state, strobe, strobe_prev, cmd_len);
    end
`endif
  end
end

endmodule
