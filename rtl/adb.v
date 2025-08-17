/*
 * Apple IIgs ADB Controller Implementation
 * 
 * This module implements the Apple Desktop Bus (ADB) controller for the Apple IIgs,
 * with full compatibility with software emulators like GSPlus and Clemens.
 *
 * Key Features:
 * - Full $C025 modifier key status register implementation
 * - Command/Option key tracking compatible with software emulators
 * - Apple IIe backwards compatibility via $C000/$C010 registers
 * - PS/2 keyboard to Apple IIgs ADB key translation
 * - Apple IIgs ADB key to Apple IIe ASCII conversion (matches GSPlus)
 * - Mouse support via ADB protocol
 * - Complete ADB device simulation (keyboard=device 2, mouse=device 3)
 * 
 * Key Conversion Pipeline:
 * PS/2 Scancode → Apple IIgs ADB Code → Apply Modifiers → Apple IIe ASCII
 *     0x1C     →        0x00        → +SHIFT        →      'A'
 * 
 * Register Compatibility:
 * $C000: Keyboard data (Apple II compatible) - contains Apple IIe ASCII characters
 * $C010: Key strobe clear (Apple II compatible) 
 * $C025: Modifier key status (bit 7=CMD, bit 6=OPTION, bit 2=CAPS, bit 1=CTRL, bit 0=SHIFT)
 * $C026: ADB command/data register
 * $C027: ADB control register
 * $C060-$C063: Joystick button registers (handled by iigs.sv main I/O decoder)
 * $C064-$C067: Paddle registers
 *
 * This implementation matches the behavior of:
 * - GSPlus emulator's adb.c (a2_key_to_ascii table and g_c025_val register)
 * - Clemens emulator's clem_adb.c (g_a2_to_ascii table)
 * - Original Apple IIgs hardware specifications
 */

module adb(
  input CLK_14M,
  input cen,
  input reset,
  input [7:0] addr,
  input rw,  // 1 for read, 0 for write
  input [7:0] din,
  output reg [7:0] dout,
  output irq,
  input strobe,
  
  // Special outputs
  output reg capslock,
  
  // PS/2 inputs
  input [10:0] ps2_key,   // [10]=toggle, [9]=pressed, [8]=extended, [7:0]=code
  input [24:0] ps2_mouse, // [24]=toggle, others=mouse data
  
  // Self-test mode override
  input selftest_override, // When high, simulates Command+Option+Control pressed
  
  // Apple IIe compatibility outputs (replacing old keyboard module)
  output reg open_apple,   // Command key for Apple IIe compatibility 
  output reg closed_apple, // Option key for Apple IIe compatibility
  output reg apple_shift,  // Shift key for Apple IIe compatibility
  output reg apple_ctrl,   // Control key for Apple IIe compatibility
  output reg akd,          // Any key down (Apple IIe compatibility)
  output [7:0] K           // Apple IIe character code with strobe bit (bit 7)
);

// ADB Controller Version - depends on ROM version
`ifdef ROM3
  parameter ADB_VERSION = 6;  // Version 6 for ROM3 (1MB Apple IIgs)
`else
  parameter ADB_VERSION = 5;  // Version 5 for ROM1 (256K Apple IIgs)  
`endif

parameter
  IDLE = 3'd0,
  CMD = 3'd1,
  DATA = 3'd2;

reg [1:0] state;
reg soft_reset;
reg [7:0] interrupt;
reg pending_irq;
reg [2:0] pending_data;
reg [31:0] data;
reg [7:0] cmd;
reg [3:0] cmd_len;
reg [15:0] cmd_timeout;  // Timeout counter for stuck commands
reg [63:0] cmd_data;
reg [7:0] adb_mode;
reg [7:0] kbd_ctl_addr = 8'd2;
reg [7:0] mouse_ctl_addr = 8'd3;
reg [7:0] repeat_rate, repeat_delay;
reg [7:0] char_set = 8'd0;
reg [7:0] layout = 8'd0;
reg [7:0] repeat_info = 8'h23;

reg data_int, mouse_int, kbd_int;
reg adb_interrupt_pending;

wire data_irq = data_int & (pending_data > 0);
wire mouse_irq = mouse_int & valid_mouse_data;
wire kbd_irq = kbd_int & kbd_strobe;  // Use strobe bit for keyboard interrupt
wire srq_irq = adb_interrupt_pending;
assign irq = data_irq | mouse_irq | kbd_irq | srq_irq;


reg valid_mouse_data;
reg valid_kbd;
reg mouse_coord;
reg cmd_full;

reg [7:0] ram[255:0];

// ADB Status/Control Registers
reg [7:0] c025_status;    // $C025 - ADB Modifier Keys Status Register
reg [7:0] c026_data;      // $C026 - ADB Command/Data Register  
reg [7:0] c027_control;   // $C027 - ADB Control Register

// Modifier key state tracking (matches software emulator g_c025_val)
reg shift_down;           // Bit 0: Shift key down
reg ctrl_down;            // Bit 1: Control key down  
reg caps_lock_down;       // Bit 2: Caps Lock down
reg option_down;          // Bit 6: Option key down
reg cmd_down;             // Bit 7: Command key down

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
reg [7:0] kbd_current_key;               // Current key in $C000
reg kbd_strobe;                          // Keyboard strobe bit

// Apple IIe compatibility - character translation and state
reg [7:0] apple_iie_char;                // Current Apple IIe character code
reg apple_iie_key_pressed;               // Apple IIe key pressed flag

// Mouse FIFO and management  
parameter MAX_MOUSE_BUF = 8;
reg [7:0] mouse_fifo [MAX_MOUSE_BUF-1:0]; // Mouse data FIFO
reg [3:0] mouse_fifo_head;               // FIFO head pointer
reg [3:0] mouse_fifo_tail;               // FIFO tail pointer
reg [3:0] mouse_fifo_count;              // Number of mouse events in FIFO


  // todo: read c024 mouse data
  // todo: read c000 - keyboard data
  // todo: access C010 - reset keydown flag bit 7 in c000
  

// PS/2 input detection
reg ps2_key_toggle_prev, ps2_mouse_toggle_prev;

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
      9'h052: ps2_to_apple_key = 8'h27;  // ' (")
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

// PS/2 Extended keys that are NOT handled in the above translation:
// Most PS/2 codes 0x085-0x110, 0x112-0x11E, 0x120-0x168, 0x16A, 0x16D-0x16F
// 0x173, 0x176-0x179, 0x17B, 0x17F and above
// These can be added later as needed for specific functionality

// Helper function: Check if Command key is down (matches software emulator)
function cmd_key_down;
  input dummy; // Verilog function needs at least one input
  cmd_key_down = cmd_down;
endfunction

// Helper function: Check if Option key is down (matches software emulator)
function option_key_down;
  input dummy;
  option_key_down = option_down;
endfunction

// Apple IIgs ADB to Apple IIe ASCII conversion (matches GSPlus emulator)
// Input: ADB key code (0x00-0x7F) + modifier flags
// Output: Apple IIe ASCII character for $C000/$C010 registers
function [7:0] adb_to_apple_iie_ascii;
  input [6:0] adb_key;     // ADB key code (0x00-0x7F)
  input       shift_mod;   // Shift modifier active
  input       ctrl_mod;    // Control modifier active  
  input       caps_mod;    // Caps lock active
  
  reg [7:0] normal_ascii;
  reg [7:0] shift_ascii;
  reg [7:0] ctrl_ascii;
  reg       is_special;
  reg       is_letter;
  
  begin
    // Default values
    normal_ascii = 8'hFF;
    shift_ascii = 8'hFF;
    ctrl_ascii = 8'hFF;
    is_special = 1'b0;
    is_letter = 1'b0;
    
    // GSPlus a2_key_to_ascii table conversion
    case(adb_key)
      // Letters (set is_letter flag for caps lock handling)
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
      7'h2A: begin normal_ascii = "\\"; shift_ascii = "|"; ctrl_ascii = 8'h1C; end // \
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
      
      // Keypad keys (important for Apple II software)
      7'h41: begin normal_ascii = "."; shift_ascii = "."; ctrl_ascii = 8'hFF; end // KP .
      7'h43: begin normal_ascii = "*"; shift_ascii = "*"; ctrl_ascii = 8'hFF; end // KP *
      7'h45: begin normal_ascii = "+"; shift_ascii = "+"; ctrl_ascii = 8'hFF; end // KP +
      7'h47: begin normal_ascii = 8'h18; shift_ascii = 8'h18; ctrl_ascii = 8'hFF; end // KP Clear
      7'h4B: begin normal_ascii = "/"; shift_ascii = "/"; ctrl_ascii = 8'hFF; end // KP /
      7'h4C: begin normal_ascii = 8'h0D; shift_ascii = 8'h0D; ctrl_ascii = 8'hFF; end // KP Enter
      7'h4E: begin normal_ascii = "-"; shift_ascii = "-"; ctrl_ascii = 8'hFF; end // KP -
      7'h51: begin normal_ascii = "="; shift_ascii = "="; ctrl_ascii = 8'hFF; end // KP =
      7'h52: begin normal_ascii = "0"; shift_ascii = "0"; ctrl_ascii = 8'hFF; end // KP 0
      7'h53: begin normal_ascii = "1"; shift_ascii = "1"; ctrl_ascii = 8'hFF; end // KP 1
      7'h54: begin normal_ascii = "2"; shift_ascii = "2"; ctrl_ascii = 8'hFF; end // KP 2
      7'h55: begin normal_ascii = "3"; shift_ascii = "3"; ctrl_ascii = 8'hFF; end // KP 3
      7'h56: begin normal_ascii = "4"; shift_ascii = "4"; ctrl_ascii = 8'hFF; end // KP 4
      7'h57: begin normal_ascii = "5"; shift_ascii = "5"; ctrl_ascii = 8'hFF; end // KP 5
      7'h58: begin normal_ascii = "6"; shift_ascii = "6"; ctrl_ascii = 8'hFF; end // KP 6
      7'h59: begin normal_ascii = "7"; shift_ascii = "7"; ctrl_ascii = 8'hFF; end // KP 7
      7'h5B: begin normal_ascii = "8"; shift_ascii = "8"; ctrl_ascii = 8'hFF; end // KP 8
      7'h5C: begin normal_ascii = "9"; shift_ascii = "9"; ctrl_ascii = 8'hFF; end // KP 9
      
      // Modifier keys (return special values to indicate they're modifiers)
      7'h36: begin normal_ascii = 8'hFF; shift_ascii = 8'hFF; ctrl_ascii = 8'hFF; is_special = 1'b1; end // Control
      7'h37: begin normal_ascii = 8'hFF; shift_ascii = 8'hFF; ctrl_ascii = 8'hFF; is_special = 1'b1; end // Command
      7'h38: begin normal_ascii = 8'hFF; shift_ascii = 8'hFF; ctrl_ascii = 8'hFF; is_special = 1'b1; end // Shift
      7'h39: begin normal_ascii = 8'hFF; shift_ascii = 8'hFF; ctrl_ascii = 8'hFF; is_special = 1'b1; end // Caps Lock
      7'h3A: begin normal_ascii = 8'hFF; shift_ascii = 8'hFF; ctrl_ascii = 8'hFF; is_special = 1'b1; end // Option
      
      default: begin 
        normal_ascii = 8'hFF; 
        shift_ascii = 8'hFF; 
        ctrl_ascii = 8'hFF; 
        is_special = 1'b1; 
      end
    endcase
    
    // Apply GSPlus modifier logic
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

// Apple IIe compatibility output assignment (matches old keyboard module)
assign K = {apple_iie_key_pressed, apple_iie_char[6:0]};

// Device command decoding (done inline in case statements)
// Also translate to Apple IIe character for compatibility
reg [7:0] iie_char;

always @(posedge CLK_14M) begin

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
    adb_interrupt_pending <= 1'b0;
    capslock <= 1'b0;
    
    // Initialize ADB controller memory/config
    adb_mode <= 8'h00;
    kbd_ctl_addr <= 8'd2;
    mouse_ctl_addr <= 8'd3;
    repeat_rate <= 8'd3;
    repeat_delay <= 8'd45;
    char_set <= 8'd0;
    layout <= 8'd0;
    repeat_info <= 8'h23;
    
    ps2_key_toggle_prev <= ps2_key[10];
    ps2_mouse_toggle_prev <= ps2_mouse[24];
    
    c025_status <= 8'h00;
    c026_data <= 8'h00;
    c027_control <= 8'h00;
    
    // Initialize modifier key states
    shift_down <= 1'b0;
    ctrl_down <= 1'b0;
    caps_lock_down <= 1'b0;
    option_down <= 1'b0;
    cmd_down <= 1'b0;
    
    // Initialize Apple IIe compatibility outputs
    open_apple <= 1'b0;
    closed_apple <= 1'b0;
    apple_shift <= 1'b0;
    apple_ctrl <= 1'b0;
    akd <= 1'b0;
    apple_iie_char <= 8'h00;
    apple_iie_key_pressed <= 1'b0;
    
    // Initialize ADB devices
    device_present <= 16'b0000_0000_0000_1100;  // Devices 2 (kbd) and 3 (mouse) present
    for (int i = 0; i < 16; i++) begin
      device_data_pending[i] <= 8'h00;
      for (int j = 0; j < 4; j++) begin
        device_registers[i][j] <= 8'h00;
      end
    end
    
    // Initialize keyboard FIFO
    kbd_fifo_head <= 4'd0;
    kbd_fifo_tail <= 4'd0;
    kbd_fifo_count <= 4'd0;
    kbd_current_key <= 8'h00;
    kbd_strobe <= 1'b0;
    for (int i = 0; i < MAX_KBD_BUF; i++) begin
      kbd_fifo[i] <= 8'h00;
    end
    
    // Initialize mouse FIFO
    mouse_fifo_head <= 4'd0;
    mouse_fifo_tail <= 4'd0;
    mouse_fifo_count <= 4'd0;
    for (int i = 0; i < MAX_MOUSE_BUF; i++) begin
      mouse_fifo[i] <= 8'h00;
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
    
    `ifdef SIMULATION
      $display("ADB: Reset - Version %d (%s)", ADB_VERSION, ADB_VERSION == 5 ? "ROM1" : "ROM3");
    `endif
  end else begin
    // Detect PS/2 input changes and update device registers
    ps2_key_toggle_prev <= ps2_key[10];
    ps2_mouse_toggle_prev <= ps2_mouse[24];
    
    // Handle PS/2 keyboard input changes
    if (ps2_key[10] != ps2_key_toggle_prev) begin
      // Translate PS/2 scancode to Apple IIgs keyboard code
      reg [7:0] apple_key;
      apple_key = ps2_to_apple_key(ps2_key[8:0]);
      
      `ifdef SIMULATION
        $display("=== ADB: PS/2 KEY CHANGE ===");
        $display("ADB: PS/2 raw input: code=$%02X, ext=%d, pressed=%d, toggle=%d", 
                 ps2_key[7:0], ps2_key[8], ps2_key[9], ps2_key[10]);
        $display("ADB: Translated PS/2 $%02X -> ADB $%02X -> IIe $%02X (%c)", 
                 ps2_key[7:0], apple_key, iie_char, 
                 (iie_char >= 32 && iie_char <= 126) ? iie_char : 8'h2E);
      `endif
      
      // Handle Caps Lock toggle (PS/2 scancode 0x58)
      if (ps2_key[8:0] == 9'h058 && ps2_key[9]) begin  // Caps Lock pressed
        capslock <= ~capslock;
        caps_lock_down <= ~caps_lock_down;
      end
      
      // Handle modifier keys (based on software emulator key codes)
      // Don't process modifier keys if selftest override is active
      if (!selftest_override) begin
        case (apple_key)
          8'h38, 8'h7B: begin // Left/Right Shift (0x38, 0x7B)
            shift_down <= ps2_key[9]; // Set when pressed, clear when released
            apple_shift <= ps2_key[9]; // Apple IIe compatibility
          end
          8'h36: begin // Control (0x36)
            ctrl_down <= ps2_key[9];
            apple_ctrl <= ps2_key[9]; // Apple IIe compatibility
          end
          8'h37: begin // Command (0x37)
            cmd_down <= ps2_key[9];
            open_apple <= ps2_key[9]; // Apple IIe compatibility (Command = Open Apple)
          end
          8'h3A: begin // Option (0x3A)
            option_down <= ps2_key[9];
            closed_apple <= ps2_key[9]; // Apple IIe compatibility (Option = Closed Apple)
          end
        endcase
      end
      
      // Convert ADB key to Apple IIe ASCII using correct conversion
      iie_char = adb_to_apple_iie_ascii(
        apple_key[6:0],      // ADB key code
        shift_down,          // Shift modifier
        ctrl_down,           // Control modifier
        caps_lock_down       // Caps lock modifier
      );
      
      // Only process valid (non-0x7F) translated keys, and skip caps lock for normal processing
      if (apple_key != 8'h7F && !(ps2_key[8:0] == 9'h058)) begin
        if (ps2_key[9]) begin  // Key pressed (not released)
          `ifdef SIMULATION
            $display("=== KEY PRESS EVENT ===");
            $display("ADB: Processing key PRESS for ADB key $%02X, IIe char $%02X (%c)", 
                     apple_key, iie_char, (iie_char >= 32 && iie_char <= 126) ? iie_char : 8'h2E);
          `endif
          
          // Add to keyboard FIFO if there's space
          if (kbd_fifo_count < MAX_KBD_BUF) begin
            kbd_fifo[kbd_fifo_head] <= apple_key;  // Store translated Apple keyboard code
            kbd_fifo_head <= (kbd_fifo_head + 1) % MAX_KBD_BUF;
            kbd_fifo_count <= kbd_fifo_count + 1;
            
            // If no current key, load immediately
            if (kbd_fifo_count == 0) begin
              kbd_current_key <= apple_key | 8'h80;  // Set strobe bit
              kbd_strobe <= 1'b1;
              `ifdef SIMULATION
                $display("ADB: Loaded key directly to current_key = $%02X (with strobe)", apple_key | 8'h80);
              `endif
              // Generate SRQ for keyboard input if enabled
              if (device_registers[2][3] & 8'h02) begin  // Check SRQ enable bit
                adb_interrupt_pending <= 1'b1;
              end
              
              // Special key combinations (matching software emulator behavior)
              // ESC + Ctrl + Cmd = Desk Manager interrupt
              if (apple_key == 8'h35 && ctrl_down && cmd_down) begin // ESC key
                adb_interrupt_pending <= 1'b1;
                `ifdef SIMULATION
                  $display("ADB: Desk Manager interrupt (Ctrl+Cmd+ESC)");
                `endif
              end
            end
            
            valid_kbd <= 1'b1;
            device_data_pending[2] <= 8'h01;
            
            // Update Apple IIe compatibility signals  
            if (iie_char != 8'hFF) begin  // Valid IIe character (not a modifier key)
              apple_iie_char <= iie_char;
              apple_iie_key_pressed <= 1'b1;
              akd <= 1'b1;  // Any key down
              `ifdef SIMULATION
                $display("ADB: Updated Apple IIe registers - char=$%02X (%c), strobe=1", 
                         iie_char, (iie_char >= 32 && iie_char <= 126) ? iie_char : 8'h2E);
              `endif
            end else begin
              // Modifier key or unmapped key - still set akd but no character
              akd <= 1'b1;  // Any key down
              `ifdef SIMULATION
                $display("ADB: Modifier/unmapped key - no Apple IIe character generated");
              `endif
            end
            
            `ifdef SIMULATION
              $display("ADB: PRESS PROCESSED - scancode=$%02X -> ADB=$%02X, ASCII=$%02X (%c), FIFO count=%d", 
                       ps2_key[7:0], apple_key, iie_char, 
                       (iie_char >= 32 && iie_char <= 126) ? iie_char : 8'h2E, kbd_fifo_count);
            `endif
          end else begin
            `ifdef SIMULATION
              $display("ADB: FIFO FULL! Cannot add key press");
            `endif
          end
        end else begin
          `ifdef SIMULATION
            $display("=== KEY RELEASE EVENT ===");
            $display("ADB: Processing key RELEASE for ADB key $%02X", apple_key);
          `endif
          
          // Key released - DO NOT add to FIFO for Apple IIe compatibility
          // Apple II only processes key presses, not releases
          
          // Update Apple IIe compatibility - key released
          if (iie_char != 8'hFF && apple_iie_char == iie_char) begin
            apple_iie_key_pressed <= 1'b0;
            if (kbd_fifo_count == 0) akd <= 1'b0;  // No more keys down
            `ifdef SIMULATION
              $display("ADB: Cleared Apple IIe strobe for released key");
            `endif
          end
          
          `ifdef SIMULATION
            $display("ADB: RELEASE PROCESSED - scancode=$%02X -> ADB=$%02X, NOT added to FIFO (Apple IIe compatibility)", 
                     ps2_key[7:0], apple_key);
          `endif
        end
      end else begin
        `ifdef SIMULATION
          $display("ADB: Unmapped PS/2 key: scancode=$%02X (extended=%d)", ps2_key[7:0], ps2_key[8]);
        `endif
      end
    end
    
    // Self-test override: simulate Command+Option+Control pressed
    // This must be outside PS/2 processing to work continuously
    if (selftest_override) begin
      cmd_down <= 1'b1;
      option_down <= 1'b1;
      ctrl_down <= 1'b1;
      open_apple <= 1'b1;   // Command = Open Apple
      closed_apple <= 1'b1; // Option = Closed Apple  
      apple_ctrl <= 1'b1;   // Control for Apple IIe compatibility
      `ifdef SIMULATION
        $display("ADB: Self-test override active - simulating Command+Option+Control pressed");
      `endif
    end
    
    // Handle PS/2 mouse input changes
    if (ps2_mouse[24] != ps2_mouse_toggle_prev) begin
      // Only process mouse data if it's meaningful (not just zeros)
      if (ps2_mouse[7:0] != 8'h00) begin
        // Add to mouse FIFO if there's space
        if (mouse_fifo_count < MAX_MOUSE_BUF) begin
          mouse_fifo[mouse_fifo_head] <= ps2_mouse[7:0];
          mouse_fifo_head <= (mouse_fifo_head + 1) % MAX_MOUSE_BUF;
          mouse_fifo_count <= mouse_fifo_count + 1;
          
          // Store current mouse data in device register
          device_registers[3][0] <= ps2_mouse[7:0];
          valid_mouse_data <= 1'b1;
          device_data_pending[3] <= 8'h01;
          
          `ifdef SIMULATION
            $display("ADB: PS/2 Mouse data: $%02X, FIFO count=%d", ps2_mouse[7:0], mouse_fifo_count + 1);
          `endif
        end
      end
    end
    
    // Timeout handling for stuck commands
    if (state == CMD) begin
      cmd_timeout <= cmd_timeout + 16'd1;
      if (cmd_timeout >= 16'd32000) begin  // ~2ms timeout at 14MHz
        `ifdef SIMULATION
          $display("ADB: Command timeout, returning to IDLE");
        `endif
        state <= IDLE;
        cmd_full <= 1'b0;
        cmd_timeout <= 16'd0;
      end
    end else begin
      cmd_timeout <= 16'd0;
    end
  end

  // Only process when strobe is active and module is enabled
  if (cen & strobe) begin
    case (addr)

    8'h00: begin
      // $C000 - Keyboard Data Register (Apple II compatible)
      // Returns Apple IIe ASCII character with strobe bit (bit 7)
      if (rw) begin
        dout <= {apple_iie_key_pressed, apple_iie_char[6:0]};  // Apple IIe format
        `ifdef SIMULATION
          $display("*** CPU READ $C000 *** Keyboard = $%02X (%c), strobe=%d", 
                   {apple_iie_key_pressed, apple_iie_char[6:0]},
                   (apple_iie_char >= 32 && apple_iie_char <= 126) ? apple_iie_char : 8'h2E,
                   apple_iie_key_pressed);
        `endif
      end
    end

    8'h10: begin
      // $C010 - Key Strobe Clear (Apple II compatible)
      if (rw) begin
        dout <= {akd, apple_iie_char[6:0]};  // Any key down + Apple IIe character
        `ifdef SIMULATION
          $display("*** CPU READ $C010 *** Strobe Clear = $%02X, akd=%d", {akd, apple_iie_char[6:0]}, akd);
        `endif
      end
      // Clear strobe on both read and write (Apple II behavior)
      `ifdef SIMULATION
        $display("*** CPU ACCESS $C010 *** Clearing keyboard strobe");
      `endif
      apple_iie_key_pressed <= 1'b0;  // Clear Apple IIe strobe
      kbd_strobe <= 1'b0;  // Clear ADB strobe
    end

    8'h25: begin
      // $C025 - ADB Modifier Keys Status Register (read-only)
      // Bit layout matches software emulator g_c025_val:
      // Bit 7: CMD_DOWN (0x80), Bit 6: OPTION_DOWN (0x40)
      // Bit 2: CAPS_LOCK_DOWN (0x04), Bit 1: CTRL_DOWN (0x02), Bit 0: SHIFT_DOWN (0x01)
      if (rw) begin
        c025_status <= {
          cmd_down,           // Bit 7 (0x80): Command key
          option_down,        // Bit 6 (0x40): Option key  
          2'b00,              // Bits 5:4 reserved
          1'b0,               // Bit 3 reserved (was keyboard strobe in some versions)
          caps_lock_down,     // Bit 2 (0x04): Caps Lock
          ctrl_down,          // Bit 1 (0x02): Control key
          shift_down          // Bit 0 (0x01): Shift key
        };
        dout <= c025_status;
        `ifdef SIMULATION
          $display("ADB: Read $C025 Modifier Status = $%02X (cmd=%d opt=%d caps=%d ctrl=%d shift=%d)", 
                   c025_status, cmd_down, option_down, caps_lock_down, ctrl_down, shift_down);
        `endif
      end
    end

    8'h26: begin
      // $C026 - ADB Command/Data Register
      if (rw) begin
        // Read $C026
        case (state)
          IDLE: begin
            dout <= data[7:0];
            if (pending_irq) dout <= 8'b0001_0000;
            if (pending_data > 3'd0) state <= DATA;
            `ifdef SIMULATION
              $display("ADB: Read $C026 IDLE = $%02X", dout);
            `endif
          end
          CMD: begin
            dout <= 8'd0;
            `ifdef SIMULATION
              $display("ADB: Read $C026 CMD = $%02X (waiting for %d more bytes)", 8'd0, cmd_len);
            `endif
          end
          DATA: begin
            dout <= data[7:0];
            data <= { 8'd0, data[31:8] };
            if (pending_data > 3'd0) pending_data <= pending_data - 3'd1;
            if (pending_data == 3'd1) state <= IDLE;
            `ifdef SIMULATION
              $display("ADB: Read $C026 DATA = $%02X, remaining=%d", dout, pending_data-1);
            `endif
          end
        endcase
      end else begin
        // Write $C026

        case (state)

          IDLE: begin
            cmd <= din;
            cmd_timeout <= 16'd0;  // Reset timeout for new command
            cmd_data <= 64'd0;     // Clear command data buffer
            
            `ifdef SIMULATION
              $display("ADB: Write $C026 Command = $%02X", din);
            `endif

            case (din)
              8'h01: begin
                // ABORT - Cancel current operation and return to IDLE
                state <= IDLE;
                cmd_full <= 1'b0;
                pending_data <= 3'd0;
                cmd_len <= 4'd0;
                `ifdef SIMULATION
                  $display("ADB: ABORT command - canceling operation");
                `endif
              end
              8'h03: begin
                // FLUSH - Clear keyboard buffer 
                // TODO: Clear keyboard FIFO when implemented
                state <= IDLE;
                cmd_full <= 1'b0;
                `ifdef SIMULATION
                  $display("ADB: FLUSH keyboard buffer");
                `endif
              end
              8'h04: begin cmd_len <= 4'd1; state <= CMD; cmd_full <= 1'b1; end
              8'h05: begin cmd_len <= 4'd1; state <= CMD; cmd_full <= 1'b1; end
              8'h06: begin cmd_len <= 4'd3; state <= CMD; cmd_full <= 1'b1; end
              8'h07: begin 
                // SYNC command - expects 1 byte mode parameter initially
                cmd_len <= 4'd1;
                state <= CMD;
                cmd_full <= 1'b1; 
                `ifdef SIMULATION
                  $display("ADB: SYNC command, expecting 1 byte");
                `endif
              end
              8'h08: begin cmd_len <= 4'd2; state <= CMD; cmd_full <= 1'b1; end
              8'h09: begin cmd_len <= 4'd2; state <= CMD; cmd_full <= 1'b1; end
              8'h0a: begin
                // Read ADB modes command
                data <= { 24'd0, adb_mode };
                pending_data <= 3'd1;
                state <= IDLE;
                `ifdef SIMULATION
                  $display("ADB: Read modes command, returning $%02X", adb_mode);
                `endif
              end
              8'h0b: begin
                // Read configuration command
                data <= {
                  8'd0,              // Reserved byte
                  mouse_ctl_addr,    // Mouse address
                  kbd_ctl_addr,      // Keyboard address  
                  repeat_info        // Repeat info
                };
                pending_data <= 3'd4;  // Return 4 bytes
                state <= IDLE;
                `ifdef SIMULATION
                  $display("ADB: Read config command, returning mouse_addr=%d, kbd_addr=%d, repeat=$%02X", 
                           mouse_ctl_addr, kbd_ctl_addr, repeat_info);
                `endif
              end
              8'h0d: begin
                // ADB Version command - return version number
                data <= { 24'd0, ADB_VERSION };  // Clear upper bits, set version in LSB
                pending_data <= 3'd1;
                state <= IDLE;  // Immediate response, return to IDLE
                cmd_full <= 1'b0;  // Clear command full flag
                `ifdef SIMULATION
                  $display("ADB: Version command, returning %d (%s)", ADB_VERSION, ADB_VERSION == 5 ? "ROM1" : "ROM3");
                `endif
              end
              8'h0e: begin // read charsets
                data <= { data[15:0], 8'd0, 8'd1 };
                pending_data <= 3'd2;
              end
              8'h0f: begin // read layouts
                data <= { data[15:0], 8'd0, 8'h1 };
                pending_data <= 3'd2;
              end
              8'h10: begin
                // SYSTEM_RESET - Reset ADB controller
                soft_reset <= 1'b1;
                `ifdef SIMULATION
                  $display("ADB: SYSTEM_RESET command");
                `endif
              end
              8'h11: begin cmd_len <= 4'd1; state <= CMD; cmd_full <= 1'b1; end
              8'h12: if (ADB_VERSION >= 6) begin cmd_len <= 4'd2; state <= CMD; cmd_full <= 1'b1; end
              8'h13: if (ADB_VERSION >= 6) begin cmd_len <= 4'd2; state <= CMD; cmd_full <= 1'b1; end
              8'h73: ; // disable SRQ on mouse
              default: begin
                // Check if this is a device command (pattern: AAAARRCCT)
                // A=address, R=register, C=command, T=type
                if (din >= 8'h10) begin  // Device commands start at 0x10
                  // Decode device command: AAAARRCCT (A=addr, R=reg, C=cmd bits)
                  case (din[1:0])  // dev_cmd bits
                    2'b01: begin // FLUSH device
                      `ifdef SIMULATION
                        $display("ADB: FLUSH device %d", din[7:4]);
                      `endif
                      state <= IDLE;
                      cmd_full <= 1'b0;
                    end
                    2'b10: begin // LISTEN (write to device)
                      if (device_present[din[7:4]]) begin
                        cmd_len <= 4'd2;  // Expect 2 data bytes for LISTEN
                        state <= CMD;
                        cmd_full <= 1'b1;  // Set command full for multi-byte command
                        `ifdef SIMULATION
                          $display("ADB: LISTEN device %d register %d", din[7:4], din[3:2]);
                        `endif
                      end else begin
                        `ifdef SIMULATION
                          $display("ADB: LISTEN to non-existent device %d", din[7:4]);
                        `endif
                        state <= IDLE;
                        cmd_full <= 1'b0;
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
                            if (device_registers[2][0] & 8'h80) valid_kbd <= 1'b0;  // Clear on key release
                          end else begin
                            data <= 32'd0;  // No data available
                            pending_data <= 3'd0;
                          end
                        end else if (din[7:4] == 4'd3 && din[3:2] == 2'd0) begin
                          // Mouse device register 0 - return mouse data if available
                          if (device_data_pending[3] > 0) begin
                            data <= { 24'd0, device_registers[3][0] };
                            pending_data <= 3'd1;
                            device_data_pending[3] <= 8'h00;  // Clear pending data
                            valid_mouse_data <= 1'b0;  // Clear flag after reading
                          end else begin
                            data <= 32'd0;  // No data available
                            pending_data <= 3'd0;
                          end
                        end else begin
                          // Return single byte device register data
                          data <= { 24'd0, device_registers[din[7:4]][din[3:2]] };
                          pending_data <= 3'd1;
                        end
                        state <= IDLE;
                        cmd_full <= 1'b0;  // Clear command full flag
                        `ifdef SIMULATION
                          $display("ADB: TALK device %d register %d = $%02X%s", din[7:4], din[3:2], 
                                   device_registers[din[7:4]][din[3:2]],
                                   (din[7:4] == 4'd2 && din[3:2] == 2'd3) ? " (2-byte kbd ID)" :
                                   (din[7:4] == 4'd3 && din[3:2] == 2'd3) ? " (2-byte mouse ID)" :
                                   (din[7:4] == 4'd2 && din[3:2] == 2'd0) ? " (keyboard data)" :
                                   (din[7:4] == 4'd3 && din[3:2] == 2'd0) ? " (mouse data)" : "");
                        `endif
                      end else begin
                        `ifdef SIMULATION
                          $display("ADB: TALK to non-existent device %d", din[7:4]);
                        `endif
                        state <= IDLE;
                        cmd_full <= 1'b0;
                      end
                    end
                    default: begin
                      `ifdef SIMULATION
                        $display("ADB: Reserved device command $%02X", din);
                      `endif
                      state <= IDLE;
                      cmd_full <= 1'b0;
                    end
                  endcase
                end else begin
                  // Non-device command - unknown
                  `ifdef SIMULATION
                    $display("ADB: Unknown/unimplemented command $%02X", din);
                  `endif
                  state <= IDLE;
                  cmd_full <= 1'b0;
                end
              end
            endcase

          end

          CMD: begin
            // Store incoming data byte in the correct position (with bounds checking)
            if (cmd_len > 4'd0 && cmd_len <= 4'd8) begin
              cmd_data[(cmd_len-1)*8+:8] <= din;
            end
            
            `ifdef SIMULATION
              $display("ADB: CMD data byte %d/%d = $%02X", 
                       (cmd_len == 4'd1) ? 1 : ((cmd_len == 4'd2) ? 2 : ((cmd_len == 4'd3) ? 3 : cmd_len)), 
                       (cmd == 8'h07) ? 1 : 
                       (cmd == 8'h06) ? 3 : 
                       (cmd == 8'h08 || cmd == 8'h09) ? 2 : cmd_len, 
                       din);
            `endif

            // Check if we have received enough data
            if (cmd_len == 4'd1) begin
              cmd_len <= 4'd0;
              state <= IDLE;
              cmd_full <= 1'b0;  // Clear command full flag
              case (cmd)
                8'h04: begin
                  // SET_MODES - Set ADB mode flags
                  adb_mode <= din | adb_mode;
                  `ifdef SIMULATION
                    $display("ADB: SET_MODES $%02X, new mode=$%02X", din, din | adb_mode);
                  `endif
                end
                8'h05: begin
                  // CLEAR_MODES - Clear ADB mode flags
                  adb_mode <= adb_mode & ~din;
                  `ifdef SIMULATION
                    $display("ADB: CLEAR_MODES $%02X, new mode=$%02X", din, adb_mode & ~din);
                  `endif
                end
                8'h06: begin 
                  // SET_CONFIG (0x06) - Configure ADB parameters (3 bytes)
                  mouse_ctl_addr <= cmd_data[23:20];
                  kbd_ctl_addr <= cmd_data[19:16];
                  repeat_delay <= din[7] ? 8'd0 : (din[7:4]+1)*8'd15;
                  case (din[3:0])
                    4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6: repeat_rate <= din[3:0]+1;
                    4'd7: repeat_rate <= 8'd15;
                    4'd8: repeat_rate <= 8'd30;
                    4'd9: repeat_rate <= 8'd60;
                  endcase
                  `ifdef SIMULATION
                    $display("ADB: SET_CONFIG - mouse_addr=%d, kbd_addr=%d, repeat_delay=%d, repeat_rate=%d", 
                             cmd_data[23:20], cmd_data[19:16], 
                             din[7] ? 0 : (din[7:4]+1)*15,
                             (din[3:0] <= 6) ? din[3:0]+1 : (din[3:0] == 7) ? 15 : (din[3:0] == 8) ? 30 : 60);
                  `endif
                end
                8'h07: begin 
                  // SYNC (0x07) - Simple mode setting with 1 byte
                  adb_mode <= din;  // Set modes directly from the data byte
                  `ifdef SIMULATION
                    $display("ADB: SYNC - mode=$%02X", din);
                  `endif
                end
                8'h08: begin
                  // WRITE_RAM - Write byte to ADB controller memory
                  ram[cmd_data[15:8]] <= din;
                  `ifdef SIMULATION
                    $display("ADB: WRITE_RAM addr=$%02X data=$%02X", cmd_data[15:8], din);
                  `endif
                end
                8'h09: begin
                  // READ_MEM - Read byte from ADB controller memory  
                  data <= { 24'd0, ram[{ din, cmd_data[15:8] }] };
                  pending_data <= 3'd1;
                  `ifdef SIMULATION
                    $display("ADB: READ_MEM addr=$%02X%02X returning=$%02X", din, cmd_data[15:8], ram[{ din, cmd_data[15:8] }]);
                  `endif
                end
                8'h11: begin
                  // SEND_KEYCODE - Send raw keycode  
                  `ifdef SIMULATION
                    $display("ADB: SEND_KEYCODE data=$%02X", din);
                  `endif
                end
                8'h12: ; // cmd 12 - ROM3 only
                8'h13: ; // cmd 13 - ROM3 only
                default: begin
                  // Check if this is a device LISTEN command that needs data
                  if (cmd >= 8'h10) begin
                    if (cmd[1:0] == 2'b10) begin // LISTEN command
                      if (device_present[cmd[7:4]]) begin
                        // Store data in device register
                        device_registers[cmd[7:4]][cmd[3:2]] <= din;
                        `ifdef SIMULATION
                          $display("ADB: LISTEN device %d register %d data=$%02X", cmd[7:4], cmd[3:2], din);
                        `endif
                      end
                    end
                  end
                end
              endcase

            end
            else begin
              // Decrement byte counter and continue receiving
              cmd_len <= cmd_len - 4'd1;
              `ifdef SIMULATION
                $display("ADB: CMD waiting for %d more bytes", cmd_len - 1);
              `endif
            end
          end


        endcase

      end

    end

    8'h27: begin
      // $C027 - ADB Control Register  
      if (rw) begin
        // Read $C027 - Status bits
        c027_control <= {
          valid_mouse_data,      // bit 7: mouse data available
          mouse_int,             // bit 6: mouse interrupt enable
          pending_data > 0 ? 1'b1 : 1'b0,  // bit 5: data valid
          data_int,              // bit 4: data interrupt enable  
          valid_kbd,             // bit 3: keyboard data valid
          kbd_int,               // bit 2: keyboard interrupt enable
          mouse_coord,           // bit 1: mouse coordinate flag
          cmd_full               // bit 0: command full
        };
        dout <= c027_control;
        
        // Auto-clear valid_mouse_data if it's been read while no pending mouse data
        if (valid_mouse_data && device_data_pending[3] == 0) begin
          valid_mouse_data <= 1'b0;
        end
        `ifdef SIMULATION
          $display("ADB: Read $C027 Control = $%02X", c027_control);
        `endif
      end else begin
        // Write $C027 - Interrupt enables
        mouse_int <= din[6];
        data_int <= din[4];
        kbd_int <= din[2];
        `ifdef SIMULATION
          $display("ADB: Write $C027 Control = $%02X (mouse_int=%d, data_int=%d, kbd_int=%d)", 
                   din, din[6], din[4], din[2]);
        `endif
      end
    end

    // $C060-$C063 - Joystick/Button registers handled by iigs.sv main I/O decoder
    // Removed from ADB module to eliminate bus conflict

    8'h64, 8'h65, 8'h66, 8'h67: begin
      // $C064-$C067 - Paddle registers (analogue joystick)
      // paddle num is addr[1:0]
      if (rw) begin
        case (addr[1:0])
          2'd0: dout <= 8'h80; // Paddle 0 - center position
          2'd1: dout <= 8'h80; // Paddle 1 - center position
          2'd2: dout <= 8'h80; // Paddle 2 - center position  
          2'd3: dout <= 8'h80; // Paddle 3 - center position
        endcase
        `ifdef SIMULATION
          $display("ADB: Read paddle %d = $%02X", addr[1:0], dout);
        `endif
      end
    end

    default: begin
      // Unhandled address
      dout <= 8'h00;
      `ifdef SIMULATION
        $display("ADB: Unhandled address $%02X", addr);
      `endif
    end

    8'h24: begin
      // $C024 - Mouse Data Register (read-only)  
      if (rw) begin
        // Return mouse data from FIFO
        if (mouse_fifo_count > 0) begin
          dout <= mouse_fifo[mouse_fifo_tail];
          mouse_fifo_tail <= (mouse_fifo_tail + 1) % MAX_MOUSE_BUF;
          mouse_fifo_count <= mouse_fifo_count - 1;
          
          // Clear mouse valid flag if FIFO is now empty
          if (mouse_fifo_count == 1) begin
            valid_mouse_data <= 1'b0;
          end
          
          `ifdef SIMULATION
            $display("ADB: Read $C024 Mouse = $%02X, FIFO count=%d", dout, mouse_fifo_count - 1);
          `endif
        end else begin
          dout <= 8'h00;  // No mouse data available
          valid_mouse_data <= 1'b0;
          `ifdef SIMULATION
            $display("ADB: Read $C024 Mouse = $00 (no data)");
          `endif
        end
      end
    end
    
    endcase
  end // if (cen & strobe)


end // always @(posedge CLK_14M)

endmodule
