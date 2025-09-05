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
  output reg [7:0] K
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

// Mouse FIFO and management  
parameter MAX_MOUSE_BUF = 8;
reg [7:0] mouse_fifo [MAX_MOUSE_BUF-1:0]; // Mouse data FIFO
reg [3:0] mouse_fifo_head;               // FIFO head pointer
reg [3:0] mouse_fifo_tail;               // FIFO tail pointer
reg [3:0] mouse_fifo_count;              // Number of mouse events in FIFO

// Modifier key tracking for selftest override and keyboard processing
reg shift_down;           // Bit 0: Shift key down
reg ctrl_down;            // Bit 1: Control key down  
reg caps_lock_down;       // Bit 2: Caps Lock down
reg option_down;          // Bit 6: Option key down
reg cmd_down;             // Bit 7: Command key down

// Key repeat - simplified VBL-based approach (like GSplus)
// Clemens approach: track PS/2 key held down and queue repeats when timers expire
reg ps2_key_held;                    // Flag indicating a PS/2 key is currently held down (no key-up received)
reg [8:0] held_ps2_key;              // The PS/2 scancode currently being held
reg [7:0] held_apple_key;            // The Apple keycode for the held key
reg [7:0] held_iie_char;             // The Apple IIe ASCII for the held key
reg [15:0] repeat_vbl_target;        // 60Hz count when next repeat should occur (16-bit to match hz60_count)
reg repeat_timer_active;             // Whether the repeat timer is running
reg k_register_updated;              // Flag: K register updated for current keypress (prevents duplicates)  
reg fifo_key_added;                  // Flag: Key added to FIFO for current keypress (prevents duplicates)
reg c010_processed_this_strobe;      // Flag: C010 write already processed this strobe transaction
reg prev_strobe;                     // Previous strobe value to detect transaction boundaries

// 60Hz clock divider for proper key repeat timing (14MHz / 233333 ≈ 60Hz)
reg [17:0] clk_60hz_counter;         // Counter for 60Hz generation (needs 18 bits for 233333)
reg clk_60hz_enable;                 // 60Hz enable pulse
reg [15:0] hz60_count;               // 60Hz tick counter for key repeat timing (16-bit to prevent overflow)
localparam CLK_60HZ_PERIOD = 18'd233333; // 14MHz / 60Hz = 233,333 clocks
reg [7:0] repeat_delay_vbl;          // Repeat delay in VBL counts
reg [7:0] repeat_rate_vbl;           // Repeat rate in VBL counts  
reg fast_repeat_enabled;             // Flag for key-specific faster repeat rates
reg [7:0] repeat_delay_setting;      // Current repeat delay setting (0-7)
reg [7:0] repeat_rate_setting;       // Current repeat rate setting (0-9)

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

// PS/2 input handling and state tracking
reg [10:0] ps2_key_prev;  // Store previous PS/2 key data to prevent duplicate processing
reg [24:0] ps2_mouse_prev;
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
    ps2_key_prev <= 11'd0;
    
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
    
    // Initialize mouse FIFO
    mouse_fifo_head <= 4'd0;
    mouse_fifo_tail <= 4'd0;
    mouse_fifo_count <= 4'd0;
    for (int i = 0; i < MAX_MOUSE_BUF; i++) begin
      mouse_fifo[i] <= 8'h00;
    end
    
    // Initialize modifier key states
    shift_down <= 1'b0;
    ctrl_down <= 1'b0;
    caps_lock_down <= 1'b0;
    option_down <= 1'b0;
    cmd_down <= 1'b0;
    
    // Initialize key repeat state - VBL based like GSplus
    ps2_key_held <= 1'b0;
    held_ps2_key <= 9'd0;
    held_apple_key <= 8'd0;
    held_iie_char <= 8'd0;
    repeat_vbl_target <= 16'd0;
    repeat_timer_active <= 1'b0;
    k_register_updated <= 1'b0;
    fifo_key_added <= 1'b0;
    c010_processed_this_strobe <= 1'b0;
    prev_strobe <= 1'b0;
    
    // Initialize 60Hz clock divider
    clk_60hz_counter <= 18'd0;
    clk_60hz_enable <= 1'b0;
    hz60_count <= 16'd0;
    repeat_delay_vbl <= 8'd30;              // Default: 30 VBL = 500ms @ 60Hz (more reasonable)
    repeat_rate_vbl <= 8'd10;               // Default: 10 VBL = ~6 repeats/sec @ 60Hz (much slower)
    fast_repeat_enabled <= 1'b0;
    repeat_delay_setting <= 8'd1;          // Default delay setting
    repeat_rate_setting <= 8'd4;           // Default rate setting
  end else begin
    // Default RAM control signals (override when needed)
    ram_wen <= 1'b0;
    
    // Track PS/2 input changes
    ps2_key_prev <= ps2_key;
    ps2_mouse_prev <= ps2_mouse;
    ps2_key_toggle_prev <= ps2_key[10];
    ps2_mouse_toggle_prev <= ps2_mouse[24];
    
    // Track strobe signal to detect transaction boundaries
    prev_strobe <= strobe;
    
    // Clear C010 processing flag when strobe goes low (end of bus transaction)
    if (prev_strobe && !strobe) begin
      c010_processed_this_strobe <= 1'b0;
    end
    
    // Generate 60Hz enable pulse from 14MHz clock
    clk_60hz_enable <= 1'b0;  // Default to no pulse
    if (clk_60hz_counter >= CLK_60HZ_PERIOD - 1) begin
      clk_60hz_counter <= 18'd0;
      clk_60hz_enable <= 1'b1;  // Generate enable pulse
      hz60_count <= hz60_count + 1;  // Increment 60Hz counter
    end else begin
      clk_60hz_counter <= clk_60hz_counter + 1;
    end
    
    // PS/2 keyboard event processing  
    if (ps2_key[10] != ps2_key_toggle_prev) begin
      // PS/2 key event detected - using wire for combinational logic
`ifdef SIMULATION
      $display("ADB: PS2 EVENT TRIGGER toggle=%0d->%0d key=%03h down=%0d", ps2_key_toggle_prev, ps2_key[10], ps2_key[8:0], ps2_key[9]);
`endif
      
      // Only process if the key scancode has actually changed OR it's a different up/down event
      if ((ps2_key[8:0] != ps2_key_prev[8:0]) || (ps2_key[9] != ps2_key_prev[9])) begin
`ifdef SIMULATION
        $display("ADB: PS2 KEY DATA CHANGED: prev=%03h->%0d new=%03h->%0d", ps2_key_prev[8:0], ps2_key_prev[9], ps2_key[8:0], ps2_key[9]);
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
      
      // Process normal keys (not modifier keys)
      begin
        reg [7:0] temp_apple_key;
        reg [7:0] temp_iie_char;
        
        temp_apple_key = ps2_to_apple_key(ps2_key[8:0]);
        
        if (temp_apple_key != 8'h7F && !(ps2_key[8:0] == 9'h058)) begin
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
            
            // Clemens approach: track this PS/2 key as held down for repeat
            if (is_repeatable_key(temp_apple_key) && temp_iie_char != 8'hFF) begin
              ps2_key_held <= 1'b1;
              held_ps2_key <= ps2_key[8:0];  // Store PS/2 scancode
              held_apple_key <= temp_apple_key;  // Store Apple keycode
              held_iie_char <= temp_iie_char;   // Store ASCII
              
              // Start repeat timer (first repeat after delay) - now using 60Hz timing
              repeat_timer_active <= 1'b1;
              repeat_vbl_target <= hz60_count + repeat_delay_vbl;
              
            end
            
            // Add to keyboard FIFO if there's space - prevent multiple additions per keypress
            if (kbd_fifo_count < MAX_KBD_BUF && !fifo_key_added) begin
              kbd_fifo[kbd_fifo_head] <= temp_apple_key;
              kbd_fifo_head <= (kbd_fifo_head + 1) % MAX_KBD_BUF;
              kbd_fifo_count <= kbd_fifo_count + 1;
              fifo_key_added <= 1'b1;  // Mark that we've added this key to FIFO
              
              // If no current key, load immediately
              if (kbd_fifo_count == 0) begin
                kbd_strobe <= 1'b1;
              end
              
              valid_kbd <= 1'b1;
              device_data_pending[2] <= 8'h01;
              
              // Update Apple IIe compatibility registers - prevent multiple updates per keypress
              if (temp_iie_char != 8'hFF && !k_register_updated) begin
                // Check if this would be a duplicate of the current K register value
                if (K[6:0] != temp_iie_char[6:0]) begin
                  $display("ADB: Setting K register for new keypress: PS2=%03h Apple=%02h ASCII=%02h K=%02h", ps2_key[8:0], temp_apple_key, temp_iie_char, {1'b1, temp_iie_char[6:0]});
                  K <= {1'b1, temp_iie_char[6:0]};  // Set strobe bit + 7-bit ASCII
                  akd <= 1'b1;  // Any key down
                  k_register_updated <= 1'b1;  // Mark that we've updated K for this keypress
                end else begin
                  $display("ADB: BLOCKED duplicate K register value: current K=%02h, attempted=%02h", K, {1'b1, temp_iie_char[6:0]});
                  k_register_updated <= 1'b1;  // Still mark as updated to prevent further attempts
                end
              end else if (temp_iie_char != 8'hFF && k_register_updated) begin
                $display("ADB: BLOCKED duplicate K register update for PS2=%03h (k_updated=%b)", ps2_key[8:0], k_register_updated);
              end
            end
          end else begin
            // Key released - stop repeat if this was the held PS/2 key
`ifdef SIMULATION
            $display("ADB: PS2 KEY UP: PS2=%03h (held=%03h held_flag=%0d)", ps2_key[8:0], held_ps2_key, ps2_key_held);
`endif
            if (ps2_key_held && (ps2_key[8:0] == held_ps2_key)) begin
              // This PS/2 key was released, stop repeating
              ps2_key_held <= 1'b0;
              repeat_timer_active <= 1'b0;
              held_ps2_key <= 9'd0;
              held_apple_key <= 8'd0;
              held_iie_char <= 8'd0;
              repeat_vbl_target <= 16'd0;
              k_register_updated <= 1'b0;  // Clear the flag so next keypress can update K
              fifo_key_added <= 1'b0;      // Clear the flag so next keypress can be added to FIFO
            end
            
            akd <= 1'b0;  // Clear any key down
          end
        end
      end
      
      // Update previous key data to prevent reprocessing
      ps2_key_prev <= ps2_key;
      end  // End of ps2_key != ps2_key_prev check
    end
    
    // Clemens approach: Check if held key should repeat - now using proper 60Hz timing!
    if (ps2_key_held && repeat_timer_active && clk_60hz_enable && (hz60_count == repeat_vbl_target)) begin
      // Time to repeat! Add the held key to the FIFO if there's space
`ifdef SIMULATION
      $display("ADB: REPEAT TRIGGER hz60=%0d target=%0d PS2=%03h fifo=%0d", hz60_count, repeat_vbl_target, held_ps2_key, kbd_fifo_count);
`endif
      if (kbd_fifo_count < MAX_KBD_BUF) begin
        kbd_fifo[kbd_fifo_head] <= held_apple_key;
        kbd_fifo_head <= (kbd_fifo_head + 1) % MAX_KBD_BUF;
        kbd_fifo_count <= kbd_fifo_count + 1;
        
        // If this is the first key in FIFO, set strobe immediately
        if (kbd_fifo_count == 0) begin
          kbd_strobe <= 1'b1;
        end
        
        valid_kbd <= 1'b1;
        device_data_pending[2] <= 8'h01;
        
        // Key repeats should NOT update K register directly - they go through FIFO 
        // The K register will be updated when the FIFO is processed by C010 reads
      end
      
      // ALWAYS update the target, even if FIFO is full - this prevents infinite repeats
      // Use fast repeat rate for specific keys if enabled
      if (fast_repeat_enabled && is_fast_repeat_key(held_apple_key)) begin
        // Fast repeat: use 2/3 of normal interval (1.5x faster) with minimum of 2 ticks
        // This prevents extremely fast repeat rates while still being noticeably faster
        repeat_vbl_target <= hz60_count + ((repeat_rate_vbl * 2) / 3 < 2 ? 2 : (repeat_rate_vbl * 2) / 3);
`ifdef SIMULATION
        $display("ADB: REPEAT scheduled FAST next at hz60=%0d (current=%0d)", hz60_count + ((repeat_rate_vbl * 2) / 3 < 2 ? 2 : (repeat_rate_vbl * 2) / 3), hz60_count);
`endif
      end else begin
        repeat_vbl_target <= hz60_count + repeat_rate_vbl;
`ifdef SIMULATION
        $display("ADB: REPEAT scheduled NORMAL next at hz60=%0d (current=%0d)", hz60_count + repeat_rate_vbl, hz60_count);
`endif
      end
    end
    
    // PS/2 mouse event processing
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
        end
      end
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
    
    // Address decoding and register access  
    if (strobe) begin
`ifdef ADB_DEBUG
      $display("ADB MODULE: strobe=1, addr=0x%02h (%d), rw=%b", addr, addr, rw);
`endif
    end
    case (addr)

      8'h25: begin
        if (rw) begin
          dout <= c025;
        end else if (cen & strobe) begin
          c025 <= din;
        end
      end

      8'h26: begin
`ifdef ADB_DEBUG
        $display("DEBUG: ADB 26 case entered, rw=%b cen=%b strobe=%b", rw, cen, strobe);
`endif
        // Read $C026 - ADB Command/Data Register
        if (rw) begin
          case (state)
            IDLE: begin
              // GSplus behavior: return interrupt byte in IDLE state
              // Set bit 3 (0x08) for keyboard SRQ when keyboard is ready
              // This is what the ROM is waiting for (>= 6 check)
              dout <= data[7:0];  // data[7:0] contains SRQ status (0x08)
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
`ifdef ADB_DEBUG
          $display("ADB_MODULE_WR_C026: cen=%b strobe=%b din=%02h [PROCESSING]", cen, strobe, din);
`endif
          case (state)

            IDLE: begin
              cmd <= din;
              cmd_timeout <= 16'd0;  // Reset timeout for new command
              cmd_data <= 64'd0;     // Clear command data buffer
              initial_cmd_len <= 4'd0; // Clear initial length
              
              case (din)
                8'h01: begin
                  // ABORT - Clear all ADB state including key repeat
                  ps2_key_held <= 1'b0;
                  repeat_timer_active <= 1'b0;
                  repeat_vbl_target <= 16'd0;
                end
                8'h03: begin
                  // FLUSH keyboard buffer - also stop key repeat
                  ps2_key_held <= 1'b0;
                  repeat_timer_active <= 1'b0;
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
                  // SYNC command - length depends on version
                  cmd_len <= (VERSION == 1) ? 4'd4 : 4'd8; 
                  initial_cmd_len <= (VERSION == 1) ? 4'd4 : 4'd8;
                  state <= CMD; 
                end
                8'h08: begin cmd_len <= 4'd2; initial_cmd_len <= 4'd2; state <= CMD; end
                8'h09: begin cmd_len <= 4'd2; initial_cmd_len <= 4'd2; state <= CMD; end
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
                  // ADB Version command - return version number
                  data <= { 24'd0, VERSION };  // Clear upper bits, set version in LSB
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
                  // Check if this is a device command (pattern: AAAARRCCT)
                  // A=address, R=register, C=command, T=type
                  if (din >= 8'h10) begin  // Device commands start at 0x10
                    // Decode device command: AAAARRCCT (A=addr, R=reg, C=cmd bits)
                    case (din[1:0])  // dev_cmd bits
                      2'b01: begin // FLUSH device
                        state <= IDLE;
                      end
                      2'b10: begin // LISTEN (write to device)
                        if (device_present[din[7:4]]) begin
                          cmd_len <= 4'd2;  // Expect 2 data bytes for LISTEN
                          initial_cmd_len <= 4'd2;
                          state <= CMD;
                        end else begin
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
                        end else begin
                          state <= IDLE;
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
              // Store incoming data byte in the correct forward order
              if (cmd_len > 0) begin
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
              end

              // Process command when enough data received
              if (cmd_len == 4'd1) begin
                cmd_len <= 4'd0;
                state <= IDLE;
                
                case (cmd)
                  8'h04: adb_mode <= din | adb_mode;
                  8'h05: adb_mode <= adb_mode & ~din;
                  8'h06: begin 
                    // SET_CONFIG (0x06) - Configure ADB parameters (3 bytes)
                    // Byte 2: mouse_ctl_addr, kbd_ctl_addr
                    // Byte 1: (reserved)
                    // Byte 0: repeat_info
                    mouse_ctl_addr <= cmd_data[23:20];
                    kbd_ctl_addr   <= cmd_data[19:16];
                    repeat_info    <= cmd_data[7:0];
                    
                    // Extract and apply repeat configuration
                    repeat_delay_setting <= cmd_data[6:4];  // Bits 6:4 = delay (0-7)
                    repeat_rate_setting  <= cmd_data[3:0];  // Bits 3:0 = rate (0-9)
                    
                    // Recalculate VBL timing values immediately
                    repeat_delay_vbl <= delay_to_vbl_count(cmd_data[6:4]);
                    repeat_rate_vbl <= rate_to_vbl_count(cmd_data[3:0], 1'b0); // No fast repeat for normal config
                  end
                  8'h07: begin 
                    // SYNC (0x07) - Multi-byte command, process all data at once
                    // Data is now stored correctly in cmd_data, apply it
                    if (initial_cmd_len == 4'd4) begin // ROM1
                      adb_mode       <= cmd_data[31:24];
                      mouse_ctl_addr <= cmd_data[23:20];
                      kbd_ctl_addr   <= cmd_data[19:16];
                      // cmd_data[15:8] is reserved
                      repeat_info    <= cmd_data[7:0];
                      
                      // Extract repeat configuration and fast repeat enable
                      repeat_delay_setting <= cmd_data[6:4];     // Bits 6:4 = delay
                      repeat_rate_setting  <= cmd_data[3:0];     // Bits 3:0 = rate
                      fast_repeat_enabled  <= (cmd_data[31:24] & 8'h08) != 8'h00; // ADB mode bit 3
                      
                      // Recalculate VBL timing values
                      repeat_delay_vbl <= delay_to_vbl_count(cmd_data[6:4]);
                      repeat_rate_vbl <= rate_to_vbl_count(cmd_data[3:0], fast_repeat_enabled);
                    end else begin // ROM3 (8 bytes)
                      // Implemented based on GSplus source
                      adb_mode       <= cmd_data[63:56];
                      mouse_ctl_addr <= cmd_data[55:52];
                      kbd_ctl_addr   <= cmd_data[51:48];
                      // cmd_data[47:40] is reserved
                      repeat_info    <= cmd_data[39:32];
                      char_set       <= cmd_data[23:16];
                      layout         <= cmd_data[15:8];
                      // cmd_data[7:0] is reserved
                      
                      // Extract repeat configuration and fast repeat enable  
                      repeat_delay_setting <= cmd_data[38:36];   // Bits 38:36 = delay
                      repeat_rate_setting  <= cmd_data[35:32];   // Bits 35:32 = rate
                      fast_repeat_enabled  <= (cmd_data[63:56] & 8'h08) != 8'h00; // ADB mode bit 3
                      
                      // Recalculate VBL timing values  
                      repeat_delay_vbl <= delay_to_vbl_count(cmd_data[38:36]);
                      repeat_rate_vbl <= rate_to_vbl_count(cmd_data[35:32], fast_repeat_enabled);
                    end
                  end
                  8'h08: begin
                    ram_addr <= cmd_data[15:8];
                    ram_din <= din;
                    ram_wen <= 1'b1;
                  end
                  8'h09: begin
                    // READ_MEM - Read byte from ADB controller memory (2 bytes)
                    // Byte 1: address high, Byte 0: address low
                    ram_addr <= cmd_data[15:8];
                    ram_wen <= 1'b0;
                    // Note: Response will be available via ram_dout in next cycle
                    data <= { 24'd0, ram_dout };
                    pending_data <= 3'd1;
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
              else begin
                cmd_len <= cmd_len - 4'd1;
              end
            end
          endcase
        end else if (strobe) begin
`ifdef ADB_DEBUG
          $display("ADB_MODULE_WR_C026: cen=%b strobe=%b din=%02h [BLOCKED - CEN NOT HIGH]", cen, strobe, din);
`endif
        end
      end

      8'h27: begin
`ifdef ADB_DEBUG
        $display("DEBUG: ADB 27 case entered, rw=%b", rw);
`endif
        // $C027 - ADB Control Register  
        if (rw) begin
          // Read $C027 - Status bits
          dout <= {
            valid_mouse_data,      // bit 7: mouse data available
            mouse_int,             // bit 6: mouse interrupt enable
            pending_data > 0 ? 1'b1 : 1'b0,  // bit 5: data valid
            data_int,              // bit 4: data interrupt enable  
            valid_kbd,             // bit 3: keyboard data valid
            kbd_int,               // bit 2: keyboard interrupt enable
            mouse_coord,           // bit 1: mouse coordinate flag
            cmd_full               // bit 0: command full
          };
`ifdef ADB_DEBUG
          $display("DEBUG: ADB 27 READ: valid_kbd=%b, kbd_int=%b, pending_data=%d, cmd_full=%b -> dout=0x%02h", 
                   valid_kbd, kbd_int, pending_data, cmd_full, 
                   {valid_mouse_data, mouse_int, pending_data > 0 ? 1'b1 : 1'b0, data_int, valid_kbd, kbd_int, mouse_coord, cmd_full});
`endif
          
          // Auto-clear valid_mouse_data if it's been read while no pending mouse data
          if (valid_mouse_data && device_data_pending[3] == 0) begin
            valid_mouse_data <= 1'b0;
          end
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
        end
      end
      
      8'h10: begin  // $C010 - Keyboard strobe clear
        if (rw) begin
          dout <= K;
        end else if (cen & strobe & !c010_processed_this_strobe) begin
`ifdef ADB_DEBUG
          $display("ADB C010 WRITE PROCESSED (cen=%b, strobe=%b, processed_flag=%b) - processing C010 clear", cen, strobe, c010_processed_this_strobe);
`endif
          $display("ADB C010: K before clear = %02h, fifo_count=%d, k_updated=%b, fifo_added=%b", K, kbd_fifo_count, k_register_updated, fifo_key_added);
          c010_processed_this_strobe <= 1'b1;  // Mark that we processed C010 this strobe transaction
          K <= {1'b0, K[6:0]};  // Clear strobe bit
          kbd_strobe <= 1'b0;  // Clear ADB strobe
          fifo_key_added <= 1'b0;      // Clear flag to allow next key to be added to FIFO
          
          // Advance FIFO to next character  
          if (kbd_fifo_count > 0) begin
            kbd_fifo_tail <= (kbd_fifo_tail + 1) % MAX_KBD_BUF;
            kbd_fifo_count <= kbd_fifo_count - 1;
            
            // Load next character if available, with simple duplicate detection
            if (kbd_fifo_count > 1) begin
              // Convert next FIFO entry to Apple IIe ASCII
              reg [7:0] next_char;
              next_char = adb_to_apple_iie_ascii(
                kbd_fifo[(kbd_fifo_tail + 1) % MAX_KBD_BUF][6:0], 
                shift_down, ctrl_down, caps_lock_state
              );
              
              // Check if next character is a duplicate and skip it
              if (next_char[6:0] == K[6:0]) begin
                $display("ADB C010: Next FIFO char is duplicate (%02h), skipping and clearing FIFO", next_char);
                // Just clear the entire remaining FIFO to prevent any more duplicates
                kbd_fifo_count <= 4'd0;
                kbd_fifo_tail <= kbd_fifo_head;
                akd <= 1'b0;
                k_register_updated <= 1'b0;
              end else begin
                // Next character is different, load it normally
                K <= {1'b1, next_char[6:0]};
                kbd_strobe <= 1'b1;
                $display("ADB C010: Loaded next FIFO char=%02h (different from current)", next_char);
                // Keep k_register_updated = 1 since we just loaded another character
              end
            end else begin
              akd <= 1'b0;  // Clear any key down status
              k_register_updated <= 1'b0;  // Only clear flag when FIFO is empty
            end
          end else begin
            k_register_updated <= 1'b0;  // Clear flag when FIFO is completely empty
          end
        end else if (cen & strobe & c010_processed_this_strobe) begin
`ifdef ADB_DEBUG
          $display("ADB C010 WRITE REJECTED - already processed this strobe transaction (cen=%b, strobe=%b)", cen, strobe);
`endif
        end else if (!cen | !strobe) begin
          // Debug when C010 write is not processed due to timing
`ifdef ADB_DEBUG
          if (strobe) $display("ADB C010 WRITE IGNORED - cen=%b strobe=%b (waiting for both)", cen, strobe);
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
          end else begin
            dout <= 8'h00;  // No mouse data available
            valid_mouse_data <= 1'b0;
          end
        end
      end

      default: dout <= 8'd0;
    endcase
  end
end

endmodule