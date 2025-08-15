
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
  
  // PS/2 inputs
  input [10:0] ps2_key,   // [10]=toggle, [9]=pressed, [8]=extended, [7:0]=code
  input [24:0] ps2_mouse  // [24]=toggle, others=mouse data
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
reg [7:0] c025_status;    // $C025 - ADB Status Register
reg [7:0] c026_data;      // $C026 - ADB Command/Data Register  
reg [7:0] c027_control;   // $C027 - ADB Control Register

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

// Device command decoding (done inline in case statements)

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
      if (ps2_key[9]) begin  // Key pressed (not released)
        // Add to keyboard FIFO if there's space
        if (kbd_fifo_count < MAX_KBD_BUF) begin
          kbd_fifo[kbd_fifo_head] <= ps2_key[7:0];  // Store PS/2 scancode
          kbd_fifo_head <= (kbd_fifo_head + 1) % MAX_KBD_BUF;
          kbd_fifo_count <= kbd_fifo_count + 1;
          
          // If no current key, load immediately
          if (kbd_fifo_count == 0) begin
            kbd_current_key <= ps2_key[7:0] | 8'h80;  // Set strobe bit
            kbd_strobe <= 1'b1;
            // Generate SRQ for keyboard input if enabled
            if (device_registers[2][3] & 8'h02) begin  // Check SRQ enable bit
              adb_interrupt_pending <= 1'b1;
            end
          end
          
          valid_kbd <= 1'b1;
          device_data_pending[2] <= 8'h01;
          
          `ifdef SIMULATION
            $display("ADB: PS/2 Key pressed: scancode=$%02X, FIFO count=%d", ps2_key[7:0], kbd_fifo_count + 1);
          `endif
        end
      end else begin
        // Key released - add release code to FIFO
        if (kbd_fifo_count < MAX_KBD_BUF) begin
          kbd_fifo[kbd_fifo_head] <= ps2_key[7:0] | 8'h80;  // Set release bit
          kbd_fifo_head <= (kbd_fifo_head + 1) % MAX_KBD_BUF;
          kbd_fifo_count <= kbd_fifo_count + 1;
          
          `ifdef SIMULATION
            $display("ADB: PS/2 Key released: scancode=$%02X", ps2_key[7:0]);
          `endif
        end
      end
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
      // $C000 - Keyboard Data Register (read-only)
      if (rw) begin
        // Return current keyboard data with strobe bit
        dout <= kbd_current_key;
        `ifdef SIMULATION
          $display("ADB: Read $C000 Keyboard = $%02X (strobe=%d)", kbd_current_key, kbd_strobe);
        `endif
      end
    end

    8'h10: begin
      // $C010 - Key Strobe Clear (any access clears strobe)
      if (rw) begin
        // Clear strobe bit and return current key data
        dout <= kbd_current_key & 8'h7F;  // Return key without strobe bit
        kbd_strobe <= 1'b0;
        kbd_current_key <= kbd_current_key & 8'h7F;  // Clear strobe bit in current key
        
        // Load next key from FIFO if available
        if (kbd_fifo_count > 0) begin
          kbd_current_key <= kbd_fifo[kbd_fifo_tail] | 8'h80;  // Set strobe bit
          kbd_strobe <= 1'b1;
          kbd_fifo_tail <= (kbd_fifo_tail + 1) % MAX_KBD_BUF;
          kbd_fifo_count <= kbd_fifo_count - 1;
        end else begin
          valid_kbd <= 1'b0;  // No more keys available
        end
        
        `ifdef SIMULATION
          $display("ADB: Read $C010 Key Strobe Clear = $%02X, FIFO count=%d", dout, kbd_fifo_count);
        `endif
      end else begin
        // Write to $C010 also clears strobe
        kbd_strobe <= 1'b0;
        kbd_current_key <= kbd_current_key & 8'h7F;
        `ifdef SIMULATION
          $display("ADB: Write $C010 Key Strobe Clear = $%02X", din);
        `endif
      end
    end

    8'h25: begin
      // $C025 - ADB Status Register (read-only)
      if (rw) begin
        dout <= c025_status;
        `ifdef SIMULATION
          $display("ADB: Read $C025 Status = $%02X", c025_status);
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

    8'h60, 8'h61, 8'h62, 8'h63: begin
      // joy num is addr[1:0]-2'd1
      dout <= 8'd0;
    end

    8'h64, 8'h65, 8'h66, 8'h67: begin
      // paddle num is addr[1:0]
      dout <= 8'd0;
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
