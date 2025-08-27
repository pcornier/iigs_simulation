module iigs
  (
   input              reset,

   input              CLK_28M,
   input              CLK_14M,
   input              clk_vid, 
   input              ce_pix, 
   input              cpu_wait,
   input [32:0]       timestamp,

     output [7:0] R,
  output [7:0] G,
  output [7:0] B,
  output HBlank,
  output VBlank,
  output HS,
  output VS,

  output phi2,
  output phi0,
  output clk_7M,

     // fastram sdram
  output [22:0] fastram_address,
  output [7:0] fastram_datatoram,
  input  [7:0] fastram_datafromram,
  output       fastram_we,
  output       fastram_ce,


 // ps2 alternative interface.
 // [8] - extended, [9] - pressed, [10] - toggles with every press/release
 input [10:0] ps2_key,
 // [24] - toggles with every event
//
//always @(posedge clk) if (clk_en) mstb <= ps2_mouse[24];
//wire       mouseStrobe = mstb ^ ps2_mouse[24];
//wire [8:0] mouseX = {ps2_mouse[4], ps2_mouse[15:8]};
//wire [8:0] mouseY = {ps2_mouse[5], ps2_mouse[23:16]};
//wire       button = ps2_mouse[0];

 input [24:0] ps2_mouse,
 
   // Self-test mode override
 input              selftest_override,

   // Floppy write-protect (sim global)
 input              floppy_wp,
   
   // Joystick and paddle inputs
   input [31:0]       joystick_0,
   input [31:0]       joystick_1,
   input [15:0]       joystick_l_analog_0,
   input [15:0]       joystick_l_analog_1,
   input [7:0]        paddle_0,
   input [7:0]        paddle_1,
   input [7:0]        paddle_2,
   input [7:0]        paddle_3,

 
   // HDD control
  output [15:0] HDD_SECTOR,
  output        HDD_READ,
  output        HDD_WRITE,
  input         HDD_MOUNTED,
  input         HDD_PROTECT,
  input [8:0]   HDD_RAM_ADDR,
  input [7:0]   HDD_RAM_DI,
  output [7:0]  HDD_RAM_DO,
  input         HDD_RAM_WE,


      // --- 5.25" floppy track interfaces (Drive 1/2) ---
   output [5:0]       TRACK1,
   output [12:0]      TRACK1_ADDR,
   output [7:0]       TRACK1_DI,
   input  [7:0]       TRACK1_DO,
   output             TRACK1_WE,
   input              TRACK1_BUSY,

   output [5:0]       TRACK2,
   output [12:0]      TRACK2_ADDR,
   output [7:0]       TRACK2_DI,
   input  [7:0]       TRACK2_DO,
   output             TRACK2_WE,
   input              TRACK2_BUSY,

   input [3:0]        DISK_READY,
   input              FLOPPY_WP,

	 output        UART_TXD,
    input         UART_RXD,
    output        UART_RTS,
    input         UART_CTS

	

);
   logic [7:0]       bank;
   logic [15:0]      addr;
   logic [7:0]       dout;
   logic       slowram_ce;
   logic       rom1_ce;
   logic       rom2_ce;
   logic       romc_ce;
   logic       romd_ce;
   logic [7:0] shadow/*verilator public_flat*/;
   logic [7:0] TEXTCOLOR;
   logic [3:0] BORDERCOLOR;
   logic [7:0] SLTROMSEL;
   logic [7:0] CYAREG;
   logic CXROM;
   logic       RDROM;
   logic       LC_WE;
   logic       LCRAM2;
   logic       PAGE2/*verilator public_flat*/;
   logic       TEXTG/*verilator public_flat*/;
   logic       MIXG/*verilator public_flat*/;
   logic       HIRES_MODE/*verilator public_flat*/;
   logic       ALTCHARSET/*verilator public_flat*/;
   logic       EIGHTYCOL/*verilator public_flat*/;
   logic       AN3/*verilator public_flat*/;
   logic [7:0] NEWVIDEO/*verilator public_flat*/;
   logic IO/*verilator public_flat*/;
   logic we;
   logic VPB;

`ifdef VERILATOR
  //parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
    parameter RAMSIZE = 20; // 16x64k = 1MB, max = 127x64k = 8MB
`else
  //parameter RAMSIZE = 15; // 16x64k = 1MB, max = 127x64k = 8MB //default 16
  parameter RAMSIZE = 127; // 16x64k = 1MB, max = 127x64k = 8MB
`endif
   logic [9:0]        H;
   logic [8:0]        V;


  logic [7:0]         bank_bef;
  logic [15:0]        addr_bef;

  logic [23:0]        cpu_addr;
  logic [7:0]         cpu_dout;
  logic [23:0]        addr_bus;
  logic [23:0]        fastram_addr_bus;
  logic               cpu_vpa, cpu_vpb;
  logic               cpu_vda, cpu_mlb;
  logic               cpu_we_n;
  logic [7:0]         io_dout;
  logic [7:0]         slot_dout;

  logic               onesecond_irq;
  logic               qtrsecond_irq;
  logic               snd_irq;

  logic               valid;

  logic [7:0]         prtc_din;
  logic [7:0]         prtc_dout;
  logic               prtc_addr;
  logic               prtc_rw, prtc_strobe;

  // Edge-detect for IRQ sources
  logic               vbl_irq_d;
  logic               qtr_irq_d;
  logic               scc_irq_d;

  logic [7:0]         adb_din;
  logic [7:0]         adb_dout;
  logic [7:0]         adb_addr;
  logic               adb_rw, adb_strobe;

  logic [7:0]         iwm_din;
  logic [7:0]         iwm_dout;
  logic [7:0]         iwm_addr;
  logic               iwm_rw, iwm_strobe;

  // Slot HDD handled externally in top.v; no internal state here

  logic [7:0]         snd_din;
  logic [7:0]         snd_dout;
  logic [1:0]         snd_addr;
  logic               snd_rw, snd_strobe;

  // SCC (Serial Communications Controller) signals
  logic [7:0]         scc_din;
  logic [7:0]         scc_dout;  
  logic               scc_cs;
  logic               scc_we;
  logic [1:0]         scc_rs;
  logic               scc_irq_n;

  logic               aux;

  // some fake registers for now
  //logic [7:0] NEWVIDEO;
  logic [7:0]         STATEREG;
  //logic [7:0]         CYAREG;
  logic [7:0]         SOUNDCTL;
  logic [7:0]         SOUNDDATA;
  logic [7:0]         DISKREG;
  //logic [7:0] SLTROMSEL;
  logic [7:0]         SOUNDADRL;
  logic [7:0]         SOUNDADRH;
  //logic [7:0] TEXTCOLOR;
  //logic ;
  logic [7:0]         SPKR;
  logic [7:0]         DISK35;
  logic [7:0]         C02BVAL;

  logic [7:0]         VGCINT; //23
  logic [7:0]         INTEN; //41
  logic [7:0]         INTFLAG; // 46, 47  AJS TODO

  logic               STORE80;
  logic               RAMRD;
  logic               RAMWRT;
  logic               INTCXROM;
  logic               ALTZP;
  logic               SLOTC3ROM;
  //logic               EIGHTYCOL;
  //logic               ALTCHARSET;
  //logic PAGE2;
  logic [7:0]         MONOCHROME;
  //logic RDROM;
  //logic LCRAM2;
  //logic LC_WE;
  logic               ROMBANK;

  logic               LC_WE_PRE;

  logic inhibit_cxxx;

  //logic TEXTG;
  //logic MIXG;

  logic               slot_area;
  logic [3:0]         slotid;

  // remap c700 to c500 if slot access and $C02D[7]
  //assign addr_bus =
  // slot_area && cpu_addr[15:8] == 8'b11000111 ? { cpu_addr[23:10], ~SLTROMSEL[7], cpu_addr[8:0] } : cpu_addr;


  logic               EXTERNAL_IO;

  logic               rom_writethrough;

  logic               lcram2_sel;

  assign VPB=cpu_vpb;
  assign CXROM=INTCXROM;
  assign { bank, addr } = addr_bus;
  assign dout = cpu_dout;
  assign we = ~cpu_we_n;
  assign valid = cpu_vpa | cpu_vda;
  
  // φ2 is a clock ENABLE, not a clock - always use CLK_14M as clock
  wire mem_clk;
  assign mem_clk = CLK_14M;

  // Revert to simpler approach - let the system boot first
  wire slowram_we;
  assign slowram_we = we && (
    // For E0/E1 Language Card areas ($D000-$FFFF), require LC_WE
    ((bank_bef == 8'he0 || bank_bef == 8'he1) && addr_bef >= 16'hd000 && addr_bef <= 16'hffff) ? LC_WE :
    // For all other slowram areas, allow normal writes
    1'b1
  );
  assign slot_area = addr[15:0] >= 16'hc100 && addr[15:0] <= 16'hcfff;
  assign slotid = addr[11:8];



  assign EXTERNAL_IO =    ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal_io);

  assign inhibit_cxxx = lcram2_sel | ((bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1) & shadow[6]);

// from c000 to c0ff only, c100 to cfff are slots or ROM based on $C02D
//wire IO = ~shadow[6] && addr[15:8] == 8'hc0 && (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1);
//assign IO =  /*~RAMRD & ~RAMWRT &*/ ~EXTERNAL_IO &  ((~shadow[6] & addr[15:8] == 8'hC0) | (shadow[6] & addr[15:13] == 3'b110)) & (bank == 8'h0 | bank == 8'h1 | bank == 8'he0 | bank == 8'he1);
  assign IO =  /*~RAMRD & ~RAMWRT &*/ ~EXTERNAL_IO &  
               (((bank == 8'h0 | bank == 8'h1) & ~shadow[6] & cpu_addr[15:8] == 8'hC0) |
                ((bank == 8'he0 | bank == 8'he1) & cpu_addr[15:8] == 8'hC0));

  // Use combinational logic but add debug to detect timing issues
  assign { bank_bef, addr_bef } = cpu_addr;
  
  // Debug: Track bank changes to detect potential timing issues
  reg [7:0] prev_bank;
  always @(posedge CLK_14M) begin
    if (phi2) begin
      if (bank_bef != prev_bank && addr_bef == 16'h0600) begin
        $display("TIMING_DEBUG: Bank changed during $0600 access: %02x -> %02x", 
                 prev_bank, bank_bef);
      end
      prev_bank <= bank_bef;
    end
  end

  always_comb begin
    lcram2_sel = 0;
    
    // E0/E1 Banks - Language Card Implementation (simplified/fixed)
    if ((bank_bef == 8'he0 || bank_bef == 8'he1) && addr_bef >= 16'hd000 && addr_bef <= 16'hdfff && LCRAM2 && ~RDROM) begin
      lcram2_sel = 1;
      if (aux && bank_bef == 8'he0) begin
        addr_bus = addr_bef - 16'h1000 + 24'h10000;
      end else begin
        addr_bus = {bank_bef, 16'h0} + addr_bef - 16'h1000;
      end
    end
    else if ((bank_bef == 8'he0 || bank_bef == 8'he1) && addr_bef >= 16'he000 && ~RDROM) begin
      lcram2_sel = 1;
      if (aux && bank_bef == 8'he0) begin
        addr_bus = addr_bef + 24'h10000;
      end else begin
        addr_bus = {bank_bef, 16'h0} + addr_bef;
      end
    end
    // Banks $00/$01 Language Card space (existing logic)
    else if ((bank_bef == 8'h00 || bank_bef == 8'h01) && addr_bef >= 16'hd000 && addr_bef <= 16'hdfff && LCRAM2 && ~shadow[6]) begin
      lcram2_sel = 1;
      if (aux && bank_bef == 8'h00) begin
        addr_bus = addr_bef - 16'h1000 + 24'h10000;
      end else begin
        addr_bus = {bank_bef, 16'h0000} + addr_bef - 16'h1000;
      end
    end
    else if ((bank_bef == 8'h00 || bank_bef == 8'h01) && addr_bef >= 16'he000 && ~RDROM && ~shadow[6]) begin
      lcram2_sel = 1;
      if (aux && bank_bef == 8'h00) begin
        addr_bus = addr_bef + 24'h10000;
      end else begin
        addr_bus = {bank_bef, 16'h0000} + addr_bef;
      end
    end
    else begin
      // Default address translation
      if (aux && (bank_bef == 8'h00 || bank_bef == 8'he0)) begin
        addr_bus = addr_bef + 24'h10000;
      end else begin
        addr_bus = cpu_addr;  // Normal mapping (includes ROM code addresses $C000-$FFFF)
      end
    end
  end

  // FastRAM uses the full address bus from CPU
  always_comb begin
    fastram_addr_bus = addr_bus;
  end

  // ============================================================================
  // CLEAN SYSTEMATIC MEMORY CONTROLLER
  // ============================================================================
  
  // Internal memory control signals
  reg fastram_ce_int;
  reg slowram_ce_int;
  
  // Assign outputs
  assign fastram_ce = fastram_ce_int;
  assign slowram_ce = slowram_ce_int;
  
  // Page and shadow detection helpers
  wire [3:0] page = addr_bef[15:12];  // 16 pages per bank (256 bytes each)
  
  // Shadow region detection (when shadow bit = 0, shadowing is ACTIVE)  
  wire txt1_shadow  = ~shadow[0] && (page == 4'h0 && addr_bef[11:8] >= 4'h4 && addr_bef[11:8] <= 4'h7);  // $0400-$07FF
  wire txt2_shadow  = ~shadow[5] && (page == 4'h0 && addr_bef[11:8] <= 4'hB && addr_bef[11:8] >= 4'h8);  // $0800-$0BFF
  wire hgr1_shadow  = ~shadow[1] && (page >= 4'h2 && page <= 4'h3);          // $2000-$3FFF
  wire hgr2_shadow  = ~shadow[2] && (page >= 4'h4 && page <= 4'h5);          // $4000-$5FFF
  wire shgr_shadow  = ~shadow[3] && (page >= 4'h6 && page <= 4'h9);          // $6000-$9FFF
  wire lc_shadow    = ~shadow[6] && (page >= 4'hC);                          // $C000-$FFFF
  wire aux_disable  = shadow[4];   // When set, disable auxiliary shadowing for bank 01
  
  // Dual-write detection: Bank 01 SHGR writes also go to Bank E1
  wire shgr_dual_write = (bank_bef == 8'h01 && shgr_shadow && we && ~IO);
  
  // Memory Controller - Clean systematic approach
  always_comb begin
    fastram_ce_int = 0;
    slowram_ce_int = 0;
    
    if (IO) begin
      // I/O space - no RAM access
      fastram_ce_int = 0;
      slowram_ce_int = 0;
    end else begin
      case (bank_bef)
        // Bank 00: Main memory with shadow regions
        8'h00: begin
          if (txt1_shadow || txt2_shadow || hgr1_shadow || hgr2_shadow || shgr_shadow || lc_shadow) begin
            // Shadowed regions: Enable BOTH for compatibility (fastram takes priority in mux)
            fastram_ce_int = 1; // Enable fastram (will be selected by priority mux)
            slowram_ce_int = 1; // Also enable slowram (for proper shadow writes)
          end else begin
            fastram_ce_int = 1;  // Normal Bank 00 RAM (non-shadowed)
          end
        end
        
        // Bank 01: Auxiliary memory with conditional shadow regions
        8'h01: begin
          if (shgr_dual_write) begin
            fastram_ce_int = 1;  // Write to both Bank 01 (FASTRAM) and Bank E1 (SLOWRAM)
            slowram_ce_int = 1;  // Dual write to E1 shadow bank
          end else if (!aux_disable && (txt1_shadow || txt2_shadow || hgr1_shadow || hgr2_shadow)) begin
            // Shadowed regions: READS from Bank 01, WRITES to both Bank 01 AND Bank E1
            fastram_ce_int = 1;   // Always access Bank 01 (for reads, and writes to original location)
            if (we) begin
              slowram_ce_int = 1; // WRITES also go to shadow Bank E1
            end
          end else if (lc_shadow) begin
            // Language card: READS from Bank 01, WRITES to both Bank 01 AND Bank E1
            fastram_ce_int = 1;   // Always access Bank 01
            if (we) begin
              slowram_ce_int = 1; // WRITES also go to shadow Bank E1
            end
          end else begin
            fastram_ce_int = 1;  // Normal Bank 01 RAM
          end
        end
        
        // Banks E0/E1: Shadow memory - always SLOWRAM
        8'hE0, 8'hE1: begin
          slowram_ce_int = 1;
        end
        
        // Banks FC-FF: ROM banks - writes should be discarded
        8'hFC, 8'hFD, 8'hFE, 8'hFF: begin
          // ROM is read-only: reads from ROM space, writes are discarded
          // Do NOT enable fastram_ce or slowram_ce for ROM writes
          // This prevents ROM selftest code from corrupting system memory
          if (~we) begin
            // ROM reads: access ROM space (handled by rom1_ce/rom2_ce signals)
            fastram_ce_int = 0;
            slowram_ce_int = 0;
          end else begin
            // ROM writes: discard (no memory access)
            fastram_ce_int = 0;
            slowram_ce_int = 0;
          end
        end
        
        // All other banks: Normal RAM (if within RAMSIZE)
        default: begin
          if ((bank_bef < RAMSIZE) && ~rom1_ce && ~rom2_ce) begin
            fastram_ce_int = 1;
          end
        end
      endcase
    end
  end

  // ROM write-through for language card
  assign rom_writethrough = (bank_bef == 8'h00 && addr_bef >= 16'hd000 && addr_bef <= 16'hffff && LC_WE);

  // Debug: Clean memory controller verification
  always @(posedge CLK_14M) begin
    // Monitor critical $6200 and $0600 range accesses for testing
    if (addr_bef == 16'h6200 || (addr_bef >= 16'h0600 && addr_bef <= 16'h0610)) begin
      if (we) begin
        if (fastram_ce_int && slowram_ce_int) begin
          $display("REFACTOR_TEST: DUAL_WRITE bank_%02x data=%02x (FASTRAM+SLOWRAM)", bank_bef, cpu_dout);
        end else if (slowram_ce_int) begin
          $display("REFACTOR_TEST: SLOWRAM_ONLY bank_%02x data=%02x", bank_bef, cpu_dout);
        end else if (fastram_ce_int) begin
          $display("REFACTOR_TEST: FASTRAM_ONLY bank_%02x data=%02x", bank_bef, cpu_dout);
        end else begin
          $display("REFACTOR_TEST: NO_RAM_ACCESS bank_%02x data=%02x (ERROR)", bank_bef, cpu_dout);
        end
      end else begin
        if (slowram_ce_int) begin
          $display("REFACTOR_TEST: READ_SLOWRAM bank_%02x (shadowed)", bank_bef);
        end else if (fastram_ce_int) begin
          $display("REFACTOR_TEST: READ_FASTRAM bank_%02x (normal)", bank_bef);
        end else begin
          $display("REFACTOR_TEST: NO_READ bank_%02x (ERROR)", bank_bef);
        end
      end
      // Debug shadow detection for these critical addresses
      if (addr_bef >= 16'h0600 && addr_bef <= 16'h0610) begin
        $display("TXT1_SHADOW_DEBUG: bank_%02x addr=%04x shadow[0]=%b txt1_shadow=%b page=%x addr[11:8]=%x", 
                 bank_bef, addr_bef, shadow[0], txt1_shadow, page, addr_bef[11:8]);
      end
      
      // Debug memory initialization for Text Page 1 range ($0400-$07FF)
      if (we && (addr_bef >= 16'h0400 && addr_bef <= 16'h07FF)) begin
        if (txt1_shadow) begin
          $display("INIT_DEBUG: TXT1_WRITE bank_%02x addr=%04x data=%02x shadow[0]=%b txt1_shadow=%b -> FASTRAM(00) + SLOWRAM(E0)", 
                   bank_bef, addr_bef, cpu_dout, shadow[0], txt1_shadow);
        end else begin
          $display("INIT_DEBUG: TXT1_WRITE bank_%02x addr=%04x data=%02x shadow[0]=%b txt1_shadow=%b -> FASTRAM(00)", 
                   bank_bef, addr_bef, cpu_dout, shadow[0], txt1_shadow);
        end
      end
      
      // Track writes near $0600 that could cause wraparound overwrites
      if (we && addr_bef >= 16'h05F8 && addr_bef <= 16'h0608 && addr_bef != 16'h0600) begin
        $display("0600_NEARBY_WRITE: bank_%02x addr=%04x data=%02x (potential wraparound)", 
                 bank_bef, addr_bef, cpu_dout);
      end
      
      // Track ALL writes to $0600 (including potential overwrites)
      if (addr_bef == 16'h0600 && we) begin
        $display("0600_ALL_WRITES: bank_%02x data=%02x addr_bus=%06x fastram_ce=%b slowram_ce=%b", 
                 bank_bef, cpu_dout, addr_bus, fastram_ce_int, slowram_ce_int);
                 
        // Memory dump after write - detailed address bus info
        $display("MEM_DUMP_POST_WRITE: addr_bus=%06x fastram_ce=%b slowram_ce=%b", 
                 addr_bus, fastram_ce_int, slowram_ce_int);
      end
      
      // Track memory enable signals for debugging
      if (addr_bef == 16'h0600) begin
        $display("0600_MEM_CYCLE: we=%b slowram_we=%b slowram_ce_int=%b slowram_ce=%b", 
                 we, slowram_we, slowram_ce_int, slowram_ce);
      end
      
      // Track specific $0600 pattern writes/reads
      if (addr_bef == 16'h0600) begin
        if (we) begin
          if (txt1_shadow) begin
            $display("0600_PATTERN_WRITE: bank_%02x data=%02x shadow[0]=%b -> Bank_00 + Bank_E0 (dual write)", 
                     bank_bef, cpu_dout, shadow[0]);
            $display("0600_WRITE_CTRL: fastram_ce=%b slowram_ce=%b addr_bus=%06x", 
                     fastram_ce_int, slowram_ce_int, addr_bus);
            $display("0600_WRITE_ADDR: fastram_addr=%06x slowram_addr=bank[0]_addr", 
                     fastram_addr_bus);
            $display("0600_WRITE_EN: fastram_we=%b slowram_we=%b mem_clk=%b CLK_14M=%b", 
                     we, slowram_we, mem_clk, CLK_14M);
            $display("0600_WRITE_TIMING: cpu_dout=%02x actual_write_data=%02x", 
                     cpu_dout, dout);
          end else begin
            $display("0600_PATTERN_WRITE: bank_%02x data=%02x shadow[0]=%b -> Bank_00", 
                     bank_bef, cpu_dout, shadow[0]);
            $display("0600_WRITE_CTRL: fastram_ce=%b slowram_ce=%b addr_bus=%06x", 
                     fastram_ce_int, slowram_ce_int, addr_bus);
          end
        end else begin
          if (bank_bef >= 8'hFC) begin
            $display("0600_PATTERN_READ: bank_%02x data=%02x shadow[0]=%b <- Bank_00 (ROM->FASTRAM)", 
                     bank_bef, cpu_din, shadow[0]);
          end else begin
            $display("0600_PATTERN_READ: bank_%02x data=%02x shadow[0]=%b <- Bank_00", 
                     bank_bef, cpu_din, shadow[0]);
          end
          
          // Enhanced read debugging - show exactly where data comes from
          $display("0600_READ_CTRL: fastram_ce=%b slowram_ce=%b addr_bus=%06x txt1_shadow=%b", 
                   fastram_ce_int, slowram_ce_int, addr_bus, txt1_shadow);
          $display("0600_READ_ADDR: fastram_addr=%06x slowram_addr=bank[0]_addr", 
                   fastram_addr_bus);
          $display("0600_READ_DATA: cpu_din=%02x fastram_data=%02x slowram_data=%02x", 
                   cpu_din, fastram_datafromram, slowram_dout);
          $display("0600_READ_EN: slowram_we=%b mem_clk=%b slowram_ce_actual=%b", 
                   slowram_we, mem_clk, slowram_ce);
          $display("0600_READ_MUX: rom1_ce=%b rom2_ce=%b IO=%b data_source=%s", 
                   rom1_ce, rom2_ce, IO, 
                   (fastram_ce_int ? "FASTRAM" : (slowram_ce_int ? "SLOWRAM" : (rom1_ce | rom2_ce ? "ROM" : "UNKNOWN"))));
        end
      end
    end
    
    // Monitor shadow register changes
    if (shadow != prev_shadow) begin
      $display("SHADOW_CHANGE: %08b -> %08b", prev_shadow, shadow);
      prev_shadow <= shadow;
    end
    
    // DEBUG: Monitor ALL memory controller logic for $0600 range (bypass all conditions)
    if (addr_bef >= 16'h0600 && addr_bef <= 16'h0610) begin
      $display("MEM_CTRL_ALL: bank_%02x addr=%04x IO=%b we=%b fastram_ce=%b slowram_ce=%b txt1_shadow=%b", 
               bank_bef, addr_bef, IO, we, fastram_ce_int, slowram_ce_int, txt1_shadow);
    end
  end
  
  reg [7:0] prev_shadow = 8'h00;

  assign romc_ce = bank_bef == 8'hfc;
  assign romd_ce = bank_bef == 8'hfd;
  assign rom1_ce = bank_bef == 8'hfe;
  assign rom2_ce = bank_bef == 8'hff ||
                   (bank_bef == 8'h0 & addr_bef >= 16'hd000 & addr_bef <= 16'hdfff && (RDROM|~VPB)) ||
                   (bank_bef == 8'h0 & addr_bef >= 16'hc000 & addr_bef <= 16'hcfff && (RDROM|~VPB)) ||
                   (bank_bef == 8'h0 & addr_bef >= 16'he000 &                     (RDROM|~VPB)) ||
                   (bank_bef == 8'h0 & addr_bef >= 16'hc070 & addr_bef <= 16'hc07f);

  // driver for io_dout and fake registers
  always_ff @(posedge CLK_14M) begin
    if (reset) begin
      // dummy values dumped from emulator
      // C036 Speed Register initialization - match GSPlus behavior
`ifdef ROM3
      CYAREG <= 8'h80; // ROM03: FAST_ENABLED (bit 7) only -> force cold boot with selftest
      $display("SPEED_REG_INIT: ROM03 detected -> CYAREG=$80 (POWERED_ON=0, FORCED cold boot, run selftest)");
`else
      CYAREG <= 8'h80; // ROM01: FAST_ENABLED (bit 7) only -> cold boot with selftest  
      $display("SPEED_REG_INIT: ROM01 detected -> CYAREG=$80 (POWERED_ON=0, cold boot, run selftest)");
`endif
      STATEREG <=  8'b0000_1101;  // GSPlus: 0x0D (rdrom, lcbank2, intcx, bit2)
      shadow <= 8'b0000_1000;  // Original value: bit 3=1 (SHGR disabled), others=0 (enabled)
      $display("SHADOW_REG_INIT: shadow=%08b (Original shadowing config)", 8'b0000_1000);
      $display("  TXT1=%b HGR1=%b HGR2=%b SHGR=%b AUX=%b TXT2=%b LC=%b", 
               1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
      $display("  Text/HGR shadowing ACTIVE, Super HiRes shadowing DISABLED");
      SOUNDCTL <= 8'd0;
      //SOUNDCTL <= 8'h05;
      NEWVIDEO <= 8'h41;
      C02BVAL <= 8'h08;

      // FROM GSPLUS
      INTCXROM<=1'b1;
      RDROM<=1'b1;
      LCRAM2<=1'b1;
      LC_WE_PRE<=1'b0;

      DISKREG<=0;
      SLTROMSEL<=0;
      TEXTCOLOR<='hf2;
      SPKR<=0;
      DISK35<=0;
      VGCINT<=0; //23
      INTEN<=0; //41
      INTFLAG<=0; // 46, 47  AJS TODO

      STORE80<=0;
      RAMRD<=0;
      RAMWRT<=0;
      INTCXROM<=0;
      ALTZP<=0;
      SLOTC3ROM<=0;
      EIGHTYCOL<=0;
      ALTCHARSET<=0;
      PAGE2<=0;
      AN3<=0;
      MONOCHROME<=0;
      RDROM<=1;
      LCRAM2<=1;  // Fix: Should be 1 to match STATEREG initialization (bit 1 = LCRAM2)
      LC_WE<=0;
      ROMBANK<=0;;
    end

    // Default pass-through for unhandled IO: feed external bus data
    io_dout <= din;
    paddle_trigger <= 1'b0;  // Default: no paddle trigger
    adb_strobe <= 1'b0;
    if (adb_strobe & cpu_we_n) begin
      io_dout <= adb_dout;
    end

    prtc_strobe <= 1'b0;
    if (prtc_strobe & cpu_we_n) begin
      io_dout <= prtc_dout;
    end

    iwm_strobe <= 1'b0;
    if (iwm_strobe & cpu_we_n & phi2) begin
      $display("read_iwm %x ret: %x GC036: %x (addr %x) cpu_addr(%x)",addr[11:0],iwm_dout,CYAREG,addr,cpu_addr);
      io_dout <= iwm_dout;
    end

    snd_strobe <= 1'b0;
    if (snd_strobe & cpu_we_n) begin
      io_dout <= snd_dout;
    end

    // Clear SCC control signals
    scc_cs <= 1'b0;
    scc_we <= 1'b0;

    if (IO) begin
      if (~cpu_we_n)
        // write
        begin
          //$display("** IO_WR %x %x",addr[11:0],cpu_dout);
          case (addr[11:0])
            12'h000: begin $display("**STORE80 %x",0); STORE80<= 1'b0 ; end
            12'h001: begin $display("**STORE80 %x",1); STORE80<= 1'b1 ; end
            12'h002: begin $display("**RAMRD %x",0); RAMRD<= 1'b0 ; end
            12'h003: begin $display("**RAMRD %x",1); RAMRD<= 1'b1 ; end
            12'h004: begin $display("**RAMWRT %x",0); RAMWRT<= 1'b0 ; end
            12'h005: begin $display("**RAMWRT %x",1); RAMWRT<= 1'b1 ; end
            12'h006: begin $display("**INTCXROM %x",0);INTCXROM<= 1'b0; end
            12'h007: begin $display("**INTCXROM %x",1);INTCXROM <= 1'b1; end
            12'h008: begin $display("**ALTZP %x",0); ALTZP<= 1'b0; end
            12'h009: begin $display("**ALTZP %x",1); ALTZP<= 1'b1; end
            12'h00A: begin $display("**SLOTC3ROM %x",0);SLOTC3ROM<= 1'b0; end
            12'h00B: begin $display("**SLOTC3ROM %x",1);SLOTC3ROM<= 1'b1; end
            12'h00C: begin $display("**EIGHTYCOL %x",0); EIGHTYCOL<= 1'b0; end
            12'h00D: begin $display("**EIGHTYCOL %x",1); EIGHTYCOL<= 1'b1; end
            12'h00E: begin $display("**ALTCHARSET %x",0); ALTCHARSET<= 1'b0; end
            12'h00F: begin $display("**ALTCHARSET %x",1); ALTCHARSET<= 1'b1; end
            12'h010, 12'h026, 12'h027, 12'h070: begin
              // Note: $C010 (key strobe clear) now handled directly by ADB module
              if (addr[11:0]==12'h070) begin
                paddle_trigger <= 1'b1;  // Trigger paddle timers
                $display("PADDLE TRIGGER");
              end
              adb_addr <= addr[7:0];
              adb_strobe <= 1'b1;
              adb_din <= cpu_dout;
              adb_rw <= 1'b0;
              $display("ADB WR %03h <= %02h", addr[11:0], cpu_dout);
            end
            12'h011,12'h12,12'h13,12'h14,12'h15,12'h16,12'h17,12'h18,12'h19,12'h1a,12'h1b,12'h1c,
              12'h01d,12'h1e,12'h1f:
                begin
                  //key_reads<=1;
                end
            12'h021: MONOCHROME <=cpu_dout;
            12'h022: TEXTCOLOR <= cpu_dout;
            12'h023: begin $display("VGCINT 23 2 %x 1 %x",cpu_dout[2],cpu_dout[1]);VGCINT <= { VGCINT[7:3],cpu_dout[2:1],VGCINT[0]} ; end // code can only modify the enable bits
            // C028: ROMBANK register does not exist as a separate register on real Apple IIgs hardware.
            // The Hardware Reference Manual states ROMBANK "must always be 0" and "do not modify this bit".
            // ROMBANK is only accessible as bit 1 of STATEREG (C068), where it exists but has no functional 
            // effect (no ROM bank switching occurs). Both KEGS and GSPlus emulators treat C028 as completely
            // unimplemented. Any software accessing C028 is likely erroneous or written for third-party cards.
            // 12'h028: [REMOVED - does not exist on real hardware]
            12'h029: begin $display("**NEWVIDEO %x",cpu_dout);NEWVIDEO <= cpu_dout; end
            12'h02b: C02BVAL <= cpu_dout; // from gsplus
            12'h02d: SLTROMSEL <= cpu_dout;
            12'h030: SPKR <= cpu_dout;
            12'h031: begin
              DISK35<= cpu_dout & 8'hc0;
`ifdef SIMULATION
              $display("IWM DBG: WR $C031 <= %02h (DISK35 bit6=%0d bit7=%0d)", cpu_dout, (cpu_dout>>6)&1'b1, (cpu_dout>>7)&1'b1);
`endif
            end
            12'h032:
              begin
                $display("VGCINT 32: bit6 %x bit5 %x",cpu_dout[6],cpu_dout[5]);
                if (cpu_dout[6]==1'b0)
                  VGCINT[6]<=1'b0;
                if (cpu_dout[5]==1'b0)
                  VGCINT[5]<=1'b0;
                // clear 7 if both are cleared
                if ((VGCINT[5]==0 || cpu_dout[5]==0) && (VGCINT[6]==0 || cpu_dout[6]==0))
                  VGCINT[7]<=1'b0;
              end
            12'h033, 12'h034: begin
              prtc_rw <= 1'b0;
              prtc_strobe <= 1'b1;
              prtc_addr <= ~addr[0];
              prtc_din <= cpu_dout;
              if (~addr[0])
                BORDERCOLOR=cpu_dout[3:0];
            end
            12'h035: begin
              $display("SHADOW_REG_WRITE: old=%08b new=%08b", shadow, cpu_dout);
              $display("  bit0(TXT1):%b->%b bit1(HGR1):%b->%b bit2(HGR2):%b->%b bit3(SHGR):%b->%b", 
                       shadow[0], cpu_dout[0], shadow[1], cpu_dout[1], shadow[2], cpu_dout[2], shadow[3], cpu_dout[3]);
              $display("  bit4(AUX):%b->%b bit5(TXT2):%b->%b bit6(LC):%b->%b bit7(RSVD):%b->%b", 
                       shadow[4], cpu_dout[4], shadow[5], cpu_dout[5], shadow[6], cpu_dout[6], shadow[7], cpu_dout[7]);
              $display("  TXT1_shadow_enable: %b->%b (0=active)", shadow[0], cpu_dout[0]);
              shadow <= cpu_dout;
            end
            12'h036: begin $display("__CYAREG %x",cpu_dout);CYAREG <= cpu_dout; end
            // SCC (Serial Communications Controller) - Zilog 8530 
            12'h038, 12'h039, 12'h03a, 12'h03b: begin
	      if (phi2) begin
              scc_cs <= 1'b1;
              scc_we <= 1'b1;
              scc_rs <= addr[1:0];  // [1]=data/ctrl, [0]=a/b port
              scc_din <= cpu_dout;
		end
            end
            12'h03c, 12'h03d, 12'h03e, 12'h03f: begin
              snd_rw <= 1'b1;
              snd_strobe <= 1'b1;
              snd_addr <= addr[1:0];
              snd_din <= cpu_dout;
              $display("SOUND WR %03h <= %02h (SNDCTL/DATA/APL/APH)", addr[11:0], cpu_dout);
            end
            12'h041: begin $display("INTEN: %02x -> %02x",INTEN,{INTEN[7:5],cpu_dout[4:0]}); INTEN <= {INTEN[7:5],cpu_dout[4:0]}; end
            12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT");
            12'h047: begin 
              $display("CLEAR INT: C047 write (CLRVBLINT) - clearing INTFLAG[4:3] vbl_irq=%0d V=%0d", vbl_irq, V);
              // Apple IIgs behavior: C047 write clears VBL and quarter-second interrupts (bits 4:3)
              INTFLAG[4:3] <= 2'b00; 
            end // clear the interrupts
            12'h050: begin $display("**TEXTG %x",0); TEXTG<=1'b0;end
            12'h051: begin $display("**TEXTG %x",1); TEXTG<=1'b1;end
            12'h052: begin $display("**MIXG %x",0); MIXG<=1'b0;end
            12'h053: begin $display("**MIXG %x",1); MIXG<=1'b1;end
            12'h054: begin $display("**PAGE2 %x",0);PAGE2<=1'b0; end
            12'h055: begin $display("**PAGE2 %x",1);PAGE2<=1'b1; end
            12'h056: begin $display("**%x",0);HIRES_MODE<=1'b0; end
            12'h057: begin $display("**%x",1);HIRES_MODE<=1'b1; end
            12'h05e: begin $display("**CLRAN3"); AN3<=1'b0; end  // CLRAN3
            12'h05f: begin $display("**SETAN3"); AN3<=1'b1; end  // SETAN3
            // $C068: bit0 stays high during boot sequence, why?
            // if bit0=1 it means that internal ROM at SCx00 is selected
            // does it mean slot cards are not accessible?
            12'h068: begin $display("** WR68: %x  ALTZP %x PAGE2 %x RAMRD %x RAMWRT %x RDROM %x LCRAM2 %x ROMBANK %x INTCXROM %x ",cpu_dout,cpu_dout[7],cpu_dout[6],cpu_dout[5],cpu_dout[4],cpu_dout[3],cpu_dout[2],cpu_dout[1],cpu_dout[0]); {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM} <= {cpu_dout[7:4],cpu_dout[3],cpu_dout[2:0]}; end
            //12'h068: begin $display("** WR68: %x  ALTZP %x PAGE2 %x RAMRD %x RAMWRT %x RDROM %x LCRAM2 %x ROMBANK %x INTCXROM %x ",cpu_dout,cpu_dout[7],cpu_dout[6],cpu_dout[5],cpu_dout[4],cpu_dout[3],cpu_dout[2],cpu_dout[1],cpu_dout[0]); {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM} <= {cpu_dout[7:4],cpu_dout[3],cpu_dout[2:0]}; end


            12'h080,	// Read RAM bank 2 no write
              12'h084:	// Read bank 2 no write
                begin
                  if (phi2) begin
                    $display("LC_WR C080/C084: RDROM=0 LCRAM2=1 LC_WE=0 (RAM read, no write)");
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b1;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h081,	// Read ROM write RAM bank 2 (RR)
              12'h085:
                begin
                  if (phi2) begin
                    $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b1;
                    LC_WE <= 1'b1;  // FIX: Enable writing (was 1'b0)
                    LC_WE_PRE<=1'b1;  // FIX: Enable pre-stage (was 1'b0)
                  end
                end
            12'h082,	// Read ROM no write
              12'h086:
                begin
                  if (phi2) begin
                    $display("LC_WR C082/C086: RDROM=1 LCRAM2=0 LC_WE=0 (ROM read, no write)");
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h083,	// Read bank 2 write bank 2(RR)
              12'h087:
                begin
                  if (phi2) begin
                    $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b1;
                    LC_WE <= 1'b1;  // FIX: Enable writing (was 1'b0)
                    LC_WE_PRE<=1'b1;  // FIX: Enable pre-stage (was 1'b0)
                  end
                end
            12'h088,
              12'h08C:
                begin
                  if (phi2) begin
                    $display("LC_WR C088/C08C: RDROM=0 LCRAM2=0 LC_WE=0 (Bank1 RAM read, no write)");
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h089,
              12'h08D:
                begin
                  if (phi2) begin
                    $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b1;  // FIX: Enable writing (was 1'b0)
                    LC_WE_PRE<=1'b1;  // FIX: Enable pre-stage (was 1'b0)
                  end
                end
            12'h08A,
              12'h08E:
                begin
                  if (phi2) begin
                    $display("LC_WR C08A/C08E: RDROM=1 LCRAM2=0 LC_WE=0 (Bank1 ROM read, no write)");
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h08B,
              12'h08F:
                begin
                  if (phi2) begin
                    $display("WRITE: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b1;  // FIX: Enable writing (was 1'b0)
                    LC_WE_PRE<=1'b1;  // FIX: Enable pre-stage (was 1'b0)
                  end
                end

            12'h0e0, 12'h0e1, 12'h0e2, 12'h0e3,
              12'h0e4, 12'h0e5, 12'h0e6, 12'h0e7,
              12'h0e8, 12'h0e9, 12'h0ea, 12'h0eb,
              12'h0ec, 12'h0ed, 12'h0ee, 12'h0ef:
                begin
                  iwm_addr <= addr[7:0];
                  iwm_strobe <= 1'b1;
                  iwm_din <= cpu_dout;
                  iwm_rw <= 1'b0;
                  $display("IWM WR %03h <= %02h", addr[11:0], cpu_dout);
                end
            // Slot IO $C0D0-$C0DF (SmartPort) and $C0F0-$C0FF handled externally at top-level. Do not override here.
            12'h0d0,12'h0d1,12'h0d2,12'h0d3,
            12'h0d4,12'h0d5,12'h0d6,12'h0d7,
            12'h0d8,12'h0d9,12'h0da,12'h0db,
            12'h0dc,12'h0dd,12'h0de,12'h0df: begin
              // no-op: external SmartPort handles this range
            end
            default:
              $display("** IO_WR %x %x",addr[11:0],cpu_dout);
          endcase
        end
      else
        begin
          // read
          //$display("** IO_RD %x, RDROM %x ",addr[11:0], RDROM);
          case (addr[11:0])
            12'h000, 12'h010, 12'h024, 12'h025,
            12'h026, 12'h027, 12'h044, 12'h045,
            12'h064, 12'h065,
            12'h066, 12'h067, 12'h070: begin
              adb_addr <= addr[7:0];
              adb_strobe <= 1'b1;
              adb_rw <= 1'b1;
              $display("ADB RD %03h", addr[11:0]);
              // Let ADB module handle all its addresses - remove hardcoded overrides
              if (addr[11:0] == 12'h070) begin  
                paddle_trigger <= 1'b1;  // Trigger paddle timers on read too
                $display("PADDLE TRIGGER (READ)");
              end
              // All ADB addresses ($C000, $C010, $C025, $C026, $C027, etc.) handled by ADB module
            end

            12'h002: begin $display("**RAMRD %x",0); RAMRD<= 1'b0 ; end
            12'h003: begin $display("**RAMRD %x",1); RAMRD<= 1'b1 ; end
            12'h004: begin $display("**RAMWRT %x",0); RAMWRT<= 1'b0 ; end
            12'h005: begin $display("**RAMWRT %x",1); RAMWRT<= 1'b1 ; end

            //12'h010: begin io_dout<=key_keys; key_reads<=1; end
            //12'h010: begin $display("anykeydown: %x",key_anykeydown); if (key_anykeydown) io_dout<='h80 | key_keys ; else io_dout<='h00; end

            12'h011: io_dout <= {LCRAM2, key_keys};
            12'h012: io_dout <= {~RDROM, key_keys};
            12'h013: io_dout <= {RAMRD, key_keys};
            12'h014: io_dout <= {RAMWRT, key_keys};
            12'h015: begin io_dout <= {INTCXROM, key_keys}; $display("read INTCXROM %x ", INTCXROM); end
            12'h016: io_dout <= {ALTZP, key_keys};
            12'h017: io_dout <= {SLOTC3ROM, key_keys};
            12'h018: io_dout <= {STORE80, key_keys};
            12'h019: io_dout <= {~VBlank, key_keys};
            12'h01a: io_dout <= {TEXTG, key_keys};
            12'h01b: io_dout <= {MIXG, key_keys};
            12'h01c: io_dout <= {PAGE2, key_keys};
            12'h01d: io_dout <= {HIRES_MODE, key_keys};
            12'h01e: io_dout <= {ALTCHARSET, key_keys};
            12'h01f: io_dout <= {EIGHTYCOL, key_keys};

            12'h022: io_dout <= TEXTCOLOR;
            12'h023: begin $display("READ VGCINT %x",VGCINT);io_dout <= VGCINT; end /* vgc int */


            // C028: ROMBANK register does not exist as a separate register on real Apple IIgs hardware.
            // See write section above for detailed explanation. Reads to C028 should also be unimplemented.
            // 12'h028: [REMOVED - does not exist on real hardware]
            12'h029: io_dout <= NEWVIDEO;
            12'h02a: io_dout <= 'h0; // from gsplus
            12'h02b: io_dout <= C02BVAL; // from gsplus
            12'h02c: io_dout <= 'h0; // from gsplus
            12'h02d: io_dout <= SLTROMSEL;
            12'h02e: io_dout <= V[8:1]; /* vertcount */
            12'h02f: io_dout <= {V[0], H[9:2]}; /* horizcount */
            12'h030: io_dout <= SPKR;
            12'h031: io_dout <= DISK35;
            12'h032: begin
              io_dout <= VGCINT; 
              VGCINT[6:5] <= 2'b00; // Clear 1-sec and scanline IRQs on read
`ifdef SIMULATION
              $display("VGCINT: Read from $C032, clearing one-second and scanline IRQ flags. VGCINT was %02h", VGCINT);
`endif
            end
            12'h033, 12'h034: begin
              prtc_addr <= ~addr[0];
              prtc_rw <= 1'b1;
              prtc_strobe <= 1'b1;
            end
            12'h035: io_dout <= shadow;
            12'h036: begin $display("__CYAREG %x",CYAREG);io_dout<=CYAREG; end
            12'h037: io_dout <= 'h0; // from gsplus

            12'h038, 12'h039, 12'h03a, 12'h03b: begin
              if (phi2)
		begin
              scc_cs <= 1'b1;
              scc_we <= 1'b0;
              scc_rs <= addr[1:0];  // [1]=data/ctrl, [0]=a/b port
              io_dout <= scc_dout;
		end
            end

            12'h03c, 12'h03d, 12'h03e, 12'h03f: begin
              snd_addr <= addr[1:0];
              snd_rw <= 1'b0;
              snd_strobe <= 1'b1;
            end
            12'h041: begin $display("read INTEN %x",INTEN);io_dout <= INTEN;end
            12'h042: $display("**++UNIMPLEMENTEDMEGAIIINTERRUPT");
            //12'h046: io_dout <=  {C046VAL[7], C046VAL[7], C046VAL[6:0]};
            12'h046: begin
              io_dout <= INTFLAG;
`ifdef SIMULATION
              $display("READ INTFLAG -> %02h vbl_irq=%0d INTFLAG[3:0]=%04b", 
                       INTFLAG, vbl_irq, INTFLAG[3:0]);
`endif
              // Real Apple IIgs behavior: reading C046 does bit manipulation (bit 7->6, clear 7)
              // But don't automatically clear interrupts - that should only happen on C047 write
              INTFLAG[6] <= INTFLAG[7];  // Move bit 7 to bit 6  
              INTFLAG[7] <= 1'b0;        // Clear bit 7
            end
            //12'h047: begin io_dout <= 'h0; C046VAL &= 'he7; end// some kind of interrupt thing
            12'h047: begin 
              $display("CLEAR INT: C047 write - clearing INTFLAG[4:3] (VBL/QTR) vbl_irq=%0d V=%0d", vbl_irq, V);
              // Apple IIgs behavior: C047 write clears VBL and quarter-second interrupts (bits 4:3)  
              // This matches emulator code: g_c046_val &= 0xe7 (clears bits 4,3)
              INTFLAG[4:3] <= 2'b00;
            end // clear the interrupts
            12'h050: begin $display("**TEXTG %x",0); TEXTG<=1'b0;end
            12'h051: begin $display("**TEXTG %x",1); TEXTG<=1'b1;end
            12'h052: begin $display("**MIXG %x",0); MIXG<=1'b0;end
            12'h053: begin $display("**MIXG %x",1); MIXG<=1'b1;end
            12'h054: begin $display("**PAGE2 %x",0);PAGE2<=1'b0; end
            12'h055: begin $display("**PAGE2 %x",1);PAGE2<=1'b1; end
            12'h056: begin $display("**%x",0);HIRES_MODE<=1'b0; end
            12'h057: begin $display("**%x",1);HIRES_MODE<=1'b1; end
            12'h058: io_dout <= 'h0; // some kind of soft switch?
            12'h05a: io_dout <= 'h0; // some kind of soft switch?
            12'h05d: io_dout <= 'h0; // some kind of soft switch?
            12'h05e: begin $display("**CLRAN3"); AN3<=1'b0; end  // CLRAN3
            12'h05f: begin $display("**SETAN3"); AN3<=1'b1; end  // SETAN3
            
            // Joystick/Paddle I/O
            12'h061: begin
              io_dout <= {sw0, 7'b0000000};                      // SW0/Open Apple (bit 7: 1=pressed)
`ifdef SIMULATION
              $display("JOYSTICK: Read button 1 ($C061) = $%02X (sw0=%d, open_apple=%d, joystick_0[4]=%d)", {sw0, 7'b0000000}, sw0, open_apple, joystick_0[4]);
`endif
            end
            12'h062: begin
              io_dout <= {sw1, 7'b0000000};                      // SW1/Closed Apple (bit 7: 1=pressed)
`ifdef SIMULATION
              $display("JOYSTICK: Read button 2 ($C062) = $%02X (sw1=%d, closed_apple=%d, joystick_0[5]=%d)", {sw1, 7'b0000000}, sw1, closed_apple, joystick_0[5]);
`endif
            end
            12'h063: io_dout <= {sw2, 7'b0000000};                      // SW2 (bit 7: 1=pressed)
            12'h064: io_dout <= {~paddle_timer_expired[0], 1'b0, ~AN3, 5'b00000}; // PADDL0 (bit 7: 1=still timing, 0=done) + AN3 (bit 5: 1=clear, 0=set)
            12'h065: io_dout <= {~paddle_timer_expired[1], 7'b0000000}; // PADDL1 (bit 7: 1=still timing, 0=done)
            12'h066: io_dout <= {~paddle_timer_expired[2], 7'b0000000}; // PADDL2 (bit 7: 1=still timing, 0=done)
            12'h067: io_dout <= {~paddle_timer_expired[3], 7'b0000000}; // PADDL3 (bit 7: 1=still timing, 0=done)
            12'h068: io_dout <= {ALTZP,PAGE2,RAMRD,RAMWRT,RDROM,LCRAM2,ROMBANK,INTCXROM};
            12'h071, 12'h072, 12'h073, 12'h074,
              12'h075, 12'h076, 12'h077, 12'h078,
              12'h079, 12'h07a, 12'h07b, 12'h07c,
              12'h07d, 12'h07e, 12'h07f:
                io_dout <= din;

            /*****************************************************************************
             * Language Card Memory
             *
             *           $C080 ;LC RAM bank2, Read and WR-protect RAM
             *ROMIN =    $C081 ;LC RAM bank2, Read ROM instead of RAM,
             *                 ;two or more successive reads WR-enables RAM
             *           $C082 ;LC RAM bank2, Read ROM instead of RAM,
             *                 ;WR-protect RAM
             *LCBANK2 =  $C083 ;LC RAM bank2, Read RAM
             *                 ;two or more successive reads WR-enables RAM
             *           $C088 ;LC RAM bank1, Read and WR-protect RAM
             *           $C089 ;LC RAM bank1, Read ROM instead of RAM,
             *                 ;two or more successive reads WR-enables RAM
             *           $C08A ;LC RAM bank1, Read ROM instead of RAM,
             *                 ;WR-protect RAM
             *LCBANK1 =  $C08B ;LC RAM bank1, Read RAM
             *                 ;two or more successive reads WR-enables RAM
             *           $C084-$C087 are echoes of $C080-$C083
             *           $C08C-$C08F are echoes of $C088-$C08B
             *
             ******************************************************************************/
            12'h080,	// Read RAM bank 2 no write
              12'h084:	// Read bank 2 no write
                begin
                  if (phi2) begin
                    $display("LC_RD C080/C084: RDROM=0 LCRAM2=1 LC_WE=0 (RAM read, no write)");
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b1;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h081,	// Read ROM write RAM bank 2 (RR)
              12'h085:
                begin
                  if (phi2) begin
                    $display("LC_RD C081/C085: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b1;
                  end
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;  // Enable write on 2nd access
                  end
                end
            12'h082,	// Read ROM no write
              12'h086:
                begin
                  if (phi2) begin
                    $display("LC_RD C082/C086: RDROM=1 LCRAM2=0 LC_WE=0 (ROM read, no write)");
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h083,	// Read bank 2 write bank 2(RR)
              12'h087:
                begin
                  if (phi2) begin
                    $display("LC_RD C083/C087: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b1;
                  end
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;  // Enable write on 2nd access
                  end
                end
            12'h088,
              12'h08C:
                begin
                  if (phi2) begin
                    $display("LC_RD C088/C08C: RDROM=0 LCRAM2=0 LC_WE=0 (Bank1 RAM read, no write)");
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h089,
              12'h08D:
                begin
                  if (phi2) begin
                    $display("LC_RD C089/C08D: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b0;
                  end
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;  // Enable write on 2nd access
                  end
                end
            12'h08A,
              12'h08E:
                begin
                  if (phi2) begin
                    $display("LC_RD C08A/C08E: RDROM=1 LCRAM2=0 LC_WE=0 (Bank1 ROM read, no write)");
                    RDROM <= 1'b1;
                    LCRAM2 <= 1'b0;
                    LC_WE <= 1'b0;
                    LC_WE_PRE<=1'b0;
                  end
                end
            12'h08B,
              12'h08F:
                begin
                  if (phi2) begin
                    $display("LC_RD C08B/C08F: ROM WRITE THROUGH LC_WE_PRE %x LC_WE %x",LC_WE_PRE,LC_WE);
                    RDROM <= 1'b0;
                    LCRAM2 <= 1'b0;
                  end
                  if (phi0) begin
                    LC_WE <= LC_WE_PRE  ;
                    LC_WE_PRE<=1'b1  ;  // Enable write on 2nd access
                  end
                end

            12'h0e0, 12'h0e1, 12'h0e2, 12'h0e3,
              12'h0e4, 12'h0e5, 12'h0e6, 12'h0e7,
              12'h0e8, 12'h0e9, 12'h0ea, 12'h0eb,
              12'h0ec, 12'h0ed, 12'h0ee, 12'h0ef:
                begin
                  iwm_addr <= addr[7:0];
                  iwm_strobe <= 1'b1;
                  iwm_rw <= 1'b1;
                  $display("IWM RD %03h -> %02h", addr[11:0], iwm_dout);
                end
            // Slot IO $C0D0-$C0DF (SmartPort) and $C0F0-$C0FF handled externally at top-level. Do not override here.
            12'h0d0,12'h0d1,12'h0d2,12'h0d3,
            12'h0d4,12'h0d5,12'h0d6,12'h0d7,
            12'h0d8,12'h0d9,12'h0da,12'h0db,
            12'h0dc,12'h0dd,12'h0de,12'h0df: begin
              // no-op: external SmartPort handles this range
            end
            default:
              $display("** IO_RD %x ",addr[11:0]);
          endcase
        end
    end

    /* *
     *  IRQ Logic
     *
     *  IIe Interrupts (INTEN/ INTFLAG):
     *  VBL - check interrupts enabled, and  intflag
     *  Quarter second (clock_frame%15?) - interrupts enabled and intflag
     *  VGC IIgs Interrupts: VGCINT
     *  1 second - interrupte enabled , VGC Interrupt
     *  scanline interrupt sets bit even if it doesn't trigger..
     * */
    //
    //VGCINT[]
    //reg [7:0] VGCINT; //23
    //reg [7:0] INTEN; //41    [0][0][0][1/4 sec][VBL][switch][move][mouse]
    //reg [7:0] INTFLAG; // 46 (47 clear)  AJS [mouse now][mouse last][an3][1/4sec][vbl][switch][move][system irq]
    VGCINT[4]<=1'b0; // EXT INT ALWAYS 0 in IIGS
    if (scanline_irq) begin
      // always set the status bit
      VGCINT[5] <= 1'b1;
`ifdef SIMULATION
      $display("VGC scanline_irq: set VGCINT[5]=1 (enable=%0d)", VGCINT[1]);
`endif
      if (VGCINT[1]) // if it is enabled, set the bit
        begin
          $display("firing scanline");
          VGCINT[7]<=1'b1;
        end
    end
    if (onesecond_irq & VGCINT[2]) begin
      VGCINT[6]<=1'b1;
      VGCINT[7]<=1'b1;
`ifdef SIMULATION
      $display("VGC 1-second irq: set VGCINT[6]=1");
`endif
    end

    // Latch VBL, quarter-second, and SCC on rising edges only
    // to avoid immediate reassert after a clear while source stays high
    vbl_irq_d <= vbl_irq;
    qtr_irq_d <= qtrsecond_irq;
    scc_irq_d <= ~scc_irq_n;  // SCC uses active-low interrupt
    
`ifdef SIMULATION
    // Debug VBL interrupt state transitions
    if (vbl_irq != vbl_irq_d) begin
      $display("VBL: vbl_irq %0d -> %0d (V=%0d H=%0d) INTEN[3]=%0d INTFLAG[3]=%0d", 
               vbl_irq_d, vbl_irq, V, H, INTEN[3], INTFLAG[3]);
    end
`endif
    
    if ((vbl_irq & ~vbl_irq_d) & INTEN[3]) begin
      INTFLAG[3]<=1'b1;
`ifdef SIMULATION
      $display("INTFLAG: set VBL (3) due vbl_irq rising edge at V=%0d H=%0d", V, H);
`endif
    end
    if ((qtrsecond_irq & ~qtr_irq_d) & INTEN[4]) begin
      INTFLAG[4]<=1'b1;
`ifdef SIMULATION
      $display("INTFLAG: set QTR (4) due qtrsecond_irq rising edge");
`endif
    end
    // SCC interrupts disabled - SCC wrapper handles interrupt masking
    // if ((~scc_irq_n & ~scc_irq_d) & INTEN[7]) begin
    //   INTFLAG[7]<=1'b1;
    // end

    // INTFLAG[0] represents pending IRQ - set when any interrupt condition is active
    // This should only be cleared when ALL interrupt sources are resolved
    // Don't recalculate every cycle to avoid race conditions with interrupt clearing
    if (INTFLAG[3] | INTFLAG[4] | VGCINT[6] | VGCINT[7] | snd_irq) begin
      INTFLAG[0] <= 1'b1;
`ifdef SIMULATION
      if (!INTFLAG[0]) begin
        $display("INTFLAG[0]: 0 -> 1 (F3=%0d F4=%0d V6=%0d V7=%0d snd=%0d)", 
                 INTFLAG[3], INTFLAG[4], VGCINT[6], VGCINT[7], snd_irq);
      end
`endif
    end else begin
      INTFLAG[0] <= 1'b0;
`ifdef SIMULATION
      if (INTFLAG[0]) begin
        $display("INTFLAG[0]: 1 -> 0 (all interrupt sources clear)");
      end
`endif
    end
    /*
     enum irq_sources
     {
     IRQS_DOC        = 0, // sound
     IRQS_SCAN       = 1,
     IRQS_ADB        = 2,
     IRQS_VBL        = 3,
     IRQS_SECOND     = 4,
     IRQS_QTRSEC     = 5,
     IRQS_SLOT       = 6,
     IRQS_SCC        = 7
     };
     */

  end
  wire cpu_irq =  (VGCINT[6]&VGCINT[2])|(VGCINT[5]&VGCINT[1])|(INTEN[3]&INTFLAG[3])|(INTEN[4]&INTFLAG[4])|snd_irq;

`ifdef SIMULATION
  // Trace sound IRQ line transitions and cpu_irq composition to verify behavior
  reg snd_irq_d;
  reg cpu_irq_d;
  reg [15:0] cpu_irq_high_cnt;
  always @(posedge CLK_14M) begin
    snd_irq_d <= snd_irq;
    cpu_irq_d <= cpu_irq;
    if (cpu_irq) cpu_irq_high_cnt <= cpu_irq_high_cnt + 16'd1; else cpu_irq_high_cnt <= 16'd0;
    if (snd_irq != snd_irq_d) begin
      $display("%m: snd_irq %0d -> %0d (VGCINT6&2=%0d VGCINT5&1=%0d INTEN3&F3=%0d INTEN4&F4=%0d INTEN7&F7=%0d)",
               snd_irq_d, snd_irq,
               (VGCINT[6]&VGCINT[2]),
               (VGCINT[5]&VGCINT[1]),
               (INTEN[3]&INTFLAG[3]),
               (INTEN[4]&INTFLAG[4]),
               (INTEN[7]&INTFLAG[7]));
    end
    if (cpu_irq != cpu_irq_d) begin
      $display("%m: cpu_irq %0d -> %0d (v1=%0d v2=%0d v3=%0d v4=%0d scc=%0d snd=%0d)",
               cpu_irq_d, cpu_irq,
               (VGCINT[6]&VGCINT[2]),
               (VGCINT[5]&VGCINT[1]),
               (INTEN[3]&INTFLAG[3]),
               (INTEN[4]&INTFLAG[4]),
               (INTEN[7]&INTFLAG[7]),
               snd_irq);
    end
    // Periodic summary when IRQ stays high too long  
    if (cpu_irq_high_cnt == 16'd2000) begin
      $display("%m: cpu_irq stuck high: INTEN=%02h INTFLAG=%02h VGCINT=%02h snd=%0d", INTEN, INTFLAG, VGCINT, snd_irq);
      // Disabled safety valve to see real interrupt behavior
      // INTFLAG[7] <= 1'b0; INTFLAG[4:3] <= 2'b00;
    end
  end
`endif


  always @(*)
    begin: aux_ctrl
      aux = 1'b0;
      if ((bank_bef==0 || bank_bef==8'he0) && (addr_bef[15:9] == 7'b0000000 | addr_bef[15:14] == 2'b11))		// Page 00,01,C0-FF
        aux = ALTZP;
      else if ((bank_bef==0 || bank_bef==1 || bank_bef==8'he0 || bank_bef==8'he1) &&  addr_bef[15:10] == 6'b000001)		// Page 04-07
        aux = ((bank_bef==1 || bank_bef==8'he1) || ((bank_bef==0 || bank_bef==8'he0) &&   ( (STORE80 & PAGE2) | ((~STORE80) & ((RAMRD & (cpu_we_n)) | (RAMWRT & ~cpu_we_n))))));
      else if (addr_bef[15:13] == 3'b001)		// Page 20-3F
        aux = ((bank_bef==1 || bank_bef==8'he1) || ((bank_bef==0 || bank_bef==8'he0) &&    ((STORE80 & PAGE2 & HIRES_MODE) | (((~STORE80) | (~HIRES_MODE)) & ((RAMRD & (cpu_we_n)) | (RAMWRT & ~cpu_we_n))))));
      else
        aux = ((bank_bef==1 || bank_bef==8'he1) || ((bank_bef==0||bank_bef==8'he0) && ((RAMRD & (cpu_we_n)) | (RAMWRT & ~cpu_we_n))));
    end
assign     fastram_address = {bank[6:0],addr};
assign     fastram_datatoram = dout;
assign     fastram_dout = fastram_datafromram;
assign     fastram_we = we;


//`define ROM3 1
`ifdef ROM3



rom #(.memfile("rom3/romc.mem")) romc(
  .clock(CLK_14M),
  .address(addr),
  .q(romc_dout),
  .ce(romc_ce)
);
rom #(.memfile("rom3/romd.mem")) romd(
  .clock(CLK_14M),
  .address(addr),
  .q(romd_dout),
  .ce(romd_ce)
);
rom #(.memfile("rom3/rom1.mem")) rom1(
  .clock(CLK_14M),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom3/rom2.mem")) rom2(
  .clock(CLK_14M),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);


`else

rom #(.memfile("rom1/rom1.mem")) rom1(
  .clock(CLK_14M),
  .address(addr),
  .q(rom1_dout),
  .ce(rom1_ce)
);

rom #(.memfile("rom1/rom2.mem")) rom2(
  .clock(CLK_14M),
  .address(addr),
  .q(rom2_dout),
  .ce(rom2_ce|slot_internalrom_ce)
);
`endif

//wire slot_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && ~is_internal;
wire slot_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~inhibit_cxxx;
wire is_internal =   ~SLTROMSEL[addr[10:8]];
wire is_internal_io =   ~SLTROMSEL[addr[6:4]];
//wire slot_internalrom_ce =  bank == 8'h0 && addr >= 'hc400 && addr < 'hc800 && is_internal;
wire slot_internalrom_ce =  (bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && is_internal && ~inhibit_cxxx;

// try to setup flags for traditional iie style slots
reg [7:0] device_select;
reg [7:0] io_select;
wire [7:0] rom1_dout, rom2_dout, romc_dout, romd_dout;
wire [7:0] fastram_dout;
wire [7:0] slowram_dout;

always @(*)
begin
   device_select=8'h0;
   io_select=8'h0;
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc090 && addr < 'hc100 && ~is_internal_io && ~inhibit_cxxx)
   begin
//	   $display("device_select addr[10:8] %x %x ISINTERNAL? ",addr[6:4],din);
          device_select[addr[6:4]]=1'b1;
  end
   if ((bank == 8'h0 || bank == 8'h1 || bank == 8'he0 || bank == 8'he1) && addr >= 'hc100 && addr < 'hc800 && ~is_internal && ~CXROM && ~inhibit_cxxx)
   begin
//	   $display("io_select addr[10:8] %x din %x HDD_DO %x fastclk %x addr %x RD %x",addr[10:8],din,HDD_DO,fast_clk,addr,we);
          io_select[addr[10:8]]=1'b1;
  end
end
`ifdef NOTDEFINED
`ifdef VERILATOR
dpram #(.widthad_a(23),.prefix("fast")) fastram
`else
dpram #(.widthad_a(16)) fastram
`endif
(
        .clock_a(clk_sys),
        .address_a({ bank[6:0], addr }),
        .data_a(dout),
        .q_a(fastram_dout),
        .wren_a(we),
        .ce_a(fastram_ce),
);
`endif


`ifdef VERILATOR
dpram #(.widthad_a(17),.prefix("slow"),.p(" e")) slowram
`else
bram #(.widthad_a(17)) slowram
`endif
(
        .clock_a(CLK_14M),
        .address_a({bank[0], addr}),
        .data_a(dout),
        .q_a(slowram_dout),
        .wren_a(slowram_we),
`ifdef VERILATOR
        .ce_a(slowram_ce),
`else
        .enable_a(slowram_ce),
`endif
        .clock_b(clk_vid),
        .address_b(video_addr[16:0]),
        .data_b(0),
        .q_b(video_data),
        .wren_b(1'b0)


        //.ce_b(1'b1)
);

video_timing video_timing(
.clk_vid(clk_vid),
.ce_pix(ce_pix),
.hsync(HS),
.vsync(VS),
.hblank(HBlank),
.vblank(VBlank),
.hpos(H),
.vpos(V)
);




wire [22:0] video_addr;
wire [7:0] video_data;
wire vbl_irq;
wire scanline_irq;


vgc vgc(
        .CLK_28M(CLK_28M),
        .CLK_14M(CLK_14M),
        .clk_vid(clk_vid),
        .ce_pix(ce_pix),
        .scanline_irq(scanline_irq),
        .vbl_irq(vbl_irq),
        .H(H),
        .V(V),
        .R(R),
        .G(G),
        .B(B),
        .video_addr(video_addr),
        .video_data(video_data),
        .TEXTCOLOR(TEXTCOLOR),
        .BORDERCOLOR(BORDERCOLOR),
        .HIRES_MODE(HIRES_MODE),
        .ALTCHARSET(ALTCHARSET),
	.AN3(AN3),
	.STORE80(STORE80),
        .EIGHTYCOL(EIGHTYCOL),
        .PAGE2(PAGE2),
        .TEXTG(TEXTG),
        .MIXG(MIXG),
        .NEWVIDEO(NEWVIDEO)
);



wire [7:0] din =
  (io_select[7] == 1'b1 | device_select[7] == 1'b1) ? HDD_DO :
  rom1_ce ? rom1_dout :
  rom2_ce ? rom2_dout :
  romc_ce ? romc_dout :
  romd_ce ? romd_dout :
  slot_internalrom_ce ?  rom2_dout :
  fastram_ce ? fastram_dout :
  slowram_ce ? slowram_dout :
  slot_ce ? slot_dout :
  8'h80;

wire [7:0] HDD_DO;

  wire [7:0] cpu_din = IO ? iwm_strobe ? iwm_dout : io_dout : din;
wire ready_out;

  P65C816 cpu(
              .CLK(CLK_14M),
              .RST_N(~reset),
              .CE(phi2),
              .RDY_IN(~cpu_wait),
              .NMI_N(1'b1),
              .IRQ_N(~cpu_irq),
              .ABORT_N(1'b1),
              .D_IN(cpu_din),
              .D_OUT(cpu_dout),
              .A_OUT(cpu_addr),
              .WE(cpu_we_n), // This signal is active low at this point
              .RDY_OUT(ready_out),
              .VPA(cpu_vpa),
              .VDA(cpu_vda),
              .MLB(cpu_mlb),
              .VPB(cpu_vpb)
              );


  always @(posedge CLK_14M)
    begin
      if (phi2)
        begin
          //$display("ready_out %x bank %x cpu_addr %x  addr_bus %x cpu_din %x cpu_dout %x cpu_we_n %x aux %x LCRAM2 %x RDROM %x LC_WE %x cpu_irq %x akd %x cpu_vpb %x RAMRD %x RDROM %x, iwm_strobe %x iwm_dout %x io_dout %x",ready_out,bank,cpu_addr,addr_bus,cpu_din,cpu_dout,cpu_we_n,aux,LCRAM2,RDROM,LC_WE,cpu_irq,key_anykeydown,cpu_vpb,RAMRD,RDROM,iwm_strobe,iwm_dout,io_dout);
          // to debug interrupts:
          if (cpu_irq)
            $display("cpu_irq %x vgc7 any %x vgc second %x vgc scanline %x second enable %x scanline enable %x INTEN[4] %x INTEN[3] %x INTFLAG 4 %x INTFLG 3 %x snd_irq %x",cpu_irq,VGCINT[7],VGCINT[6],VGCINT[5],VGCINT[2],VGCINT[1],INTEN[4],INTEN[3],INTFLAG[4],INTFLAG[3], snd_irq);
        end
    end


`ifdef VERILATOR
  reg [19:0] dbg_pc_counter;
  always @(posedge cpu_vpa or posedge cpu_vda or posedge reset)
    if (reset)
      dbg_pc_counter <= 20'd0;
    else if (cpu_vpa & cpu_vda)
      dbg_pc_counter <= dbg_pc_counter + 20'd1;
`endif

  wire adb_capslock;
  wire adb_open_apple, adb_closed_apple, adb_shift, adb_ctrl;
  wire adb_akd;
  wire [7:0] adb_K;
  
  adb adb(
          .CLK_14M(CLK_14M),
          .cen(phi2),
          .reset(reset),
          .addr(adb_addr),
          .rw(adb_rw),
          .din(adb_din),
          .dout(adb_dout),
          .irq(/* unused - ADB IRQ handled via registers */),
          .strobe(adb_strobe),
          .capslock(adb_capslock),
          .ps2_key(ps2_key),
          .ps2_mouse(ps2_mouse),
          .selftest_override(selftest_override), // Self-test mode override
          .vbl_count(V[8:0]),              // VBL counter for key repeat timing
          // Apple IIe compatibility outputs (replacing old keyboard module)
          .open_apple(adb_open_apple),     // Command key = Open Apple
          .closed_apple(adb_closed_apple), // Option key = Closed Apple
          .apple_shift(adb_shift),         // Shift key
          .apple_ctrl(adb_ctrl),           // Control key
          .akd(adb_akd),                   // Any key down
          .K(adb_K)                        // Apple IIe character with strobe
          );

  prtc prtc(
            .CLK_14M(CLK_14M),
            .cen(phi2),
            .timestamp(timestamp),
            .reset(reset),
            .addr(prtc_addr),
            .din(prtc_din),
            .dout(prtc_dout),
            .onesecond_irq(onesecond_irq),
            .qtrsecond_irq(qtrsecond_irq),
            .rw(prtc_rw),
            .strobe(prtc_strobe)
            );

`ifdef IWMSTUB
  iwm iwm(
          .CLK_14M(CLK_14M),
          .cen(q3_en),
          .reset(reset),
          .addr(iwm_addr),
          .din(iwm_din),
          .dout(iwm_dout),
          .rw(iwm_rw),
          .strobe(iwm_strobe),
          .DISK35(DISK35)
          );
  `else
        iwm_controller iwmc (
      // Global clocks/resets
      .CLK_14M(CLK_14M),
      .CLK_7M_EN(clk_7M_en),
      .Q3(q3_en),
      .PH0(phi0),
      .RESET(reset),
      // Bus interface
      .IO_SELECT(iwm_strobe),
      .DEVICE_SELECT(iwm_strobe),
      .WR_CYCLE(iwm_rw),
      //.ACCESS_STROBE(iwm_strobe),
      .A(iwm_addr),
      .D_IN(iwm_din),
      .D_OUT(iwm_dout),
      // Drive status and control
      .DISK_READY(DISK_READY),
      .DISK35(DISK35),
      .WRITE_PROTECT(floppy_wp),
      // 5.25" Drive 1
      .TRACK1(TRACK1),
      .TRACK1_ADDR(TRACK1_ADDR),
      .TRACK1_DI(TRACK1_DI),
      .TRACK1_DO(TRACK1_DO),
      .TRACK1_WE(TRACK1_WE),
      .TRACK1_BUSY(TRACK1_BUSY),
      // 5.25" Drive 2
      .TRACK2(TRACK2),
      .TRACK2_ADDR(TRACK2_ADDR),
      .TRACK2_DI(TRACK2_DI),
      .TRACK2_DO(TRACK2_DO),
      .TRACK2_WE(TRACK2_WE),
      .TRACK2_BUSY(TRACK2_BUSY),
      // 3.5" not yet wired
      .TRACK3(), .TRACK3_ADDR(), .TRACK3_SIDE(), .TRACK3_DI(), .TRACK3_DO(8'h00), .TRACK3_WE(), .TRACK3_BUSY(1'b0),
      .TRACK4(), .TRACK4_ADDR(), .TRACK4_SIDE(), .TRACK4_DI(), .TRACK4_DO(8'h00), .TRACK4_WE(), .TRACK4_BUSY(1'b0)
  );
  `endif

    // Legacy slot-7 HDD 
    hdd hdd(
        .CLK_14M(CLK_14M),
        .phi0(phi0),
        .IO_SELECT(io_select[7]),
        .DEVICE_SELECT(device_select[7]),
        //.IO_SELECT(1'b0),
        //.DEVICE_SELECT(1'b0),
        .RESET(reset),
        .A(addr),
        .RD(~we),
        .D_IN(dout),
        .D_OUT(HDD_DO),
        .sector(HDD_SECTOR),
        .hdd_read(HDD_READ),
        .hdd_write(HDD_WRITE),
        .hdd_mounted(HDD_MOUNTED),
        .hdd_protect(HDD_PROTECT),
        .ram_addr(HDD_RAM_ADDR),
        .ram_di(HDD_RAM_DI),
        .ram_do(HDD_RAM_DO),
        .ram_we(HDD_RAM_WE)
    );
/*
    // Native SmartPort HDD on Slot 5 ($C0D0–$C0DF), no ROM
    sp_hdd sp_hdd(
        .CLK_14M(CLK_14M),
        .phi0(phi0),
        .IO_SELECT(io_select[5]),
        .DEVICE_SELECT(device_select[5]),
        .RESET(reset),
        .A(addr),
        .RD(~we),
        .D_IN(dout),
        .D_OUT(SP_DO),
        .sector(HDD_SECTOR),
        .hdd_read(HDD_READ),
        .hdd_write(HDD_WRITE),
        .hdd_mounted(HDD_MOUNTED),
        .hdd_protect(HDD_PROTECT),
        .ram_addr(HDD_RAM_ADDR),
        .ram_di(HDD_RAM_DI),
        .ram_do(HDD_RAM_DO),cpu_we_n
        .ram_we(HDD_RAM_WE)
    );
*/
  sound snd(
            .CLK_14M(CLK_14M),
            .ph0_en(phi0),
            .reset(reset),
            .select(snd_strobe),
            .wr(snd_rw),
            .host_addr(snd_addr),
            .host_data_in(snd_din),
            .host_data_out(snd_dout),
            .irq(snd_irq)
            );

  // SCC (Serial Communications Controller) - Zilog 8530
  scc_iigs_wrapper scc_inst(
            .clk_14m(CLK_14M),
            .ph0_en(phi0),
            .q3_en(q3_en),
            .reset(reset),
            .cs(scc_cs),
            .we(scc_we),
            .rs(scc_rs),
            .wdata(scc_din),
            .rdata(scc_dout),
            .irq_n(scc_irq_n),
            // Serial ports - stubbed for now
            .txd_a(UART_TXD),
            .txd_b(),
            .rxd_a(UART_RXD),
            .rxd_b(1'b1),
            .rts_a(UART_RTS),
            .rts_b(),
            .cts_a(UART_CTS),
            .cts_b(1'b0)
				);

  // Apple IIe compatibility signals now come from ADB module
  wire [6:0] key_keys = adb_K[6:0];        // Use ADB's Apple IIe character output
  //wire       key_anykeydown = adb_akd;     // Any key down from ADB
  wire       open_apple = adb_open_apple;  // Command key from ADB
  wire       closed_apple = adb_closed_apple; // Option key from ADB
  
  // Old keyboard module removed - ADB now handles all keyboard functionality
  // key_reads variable removed - ADB handles $C010 strobe clearing internally

  // === Joystick/Paddle Support ===
  
  // Choose paddle input source (can switch between paddle and analog stick)
  wire [7:0] paddle_input[3:0];
  `ifdef USE_ANALOG_STICK
    // Use analog sticks as paddles (convert signed to unsigned)
    assign paddle_input[0] = {~joystick_l_analog_0[7], joystick_l_analog_0[6:0]};  // X
    assign paddle_input[1] = {~joystick_l_analog_0[15], joystick_l_analog_0[14:8]}; // Y
    assign paddle_input[2] = {~joystick_l_analog_1[7], joystick_l_analog_1[6:0]};  
    assign paddle_input[3] = {~joystick_l_analog_1[15], joystick_l_analog_1[14:8]};
  `else
    // Use dedicated paddle inputs (default)
    assign paddle_input[0] = paddle_0;
    assign paddle_input[1] = paddle_1;
    assign paddle_input[2] = paddle_2; 
    assign paddle_input[3] = paddle_3;
  `endif

  // Paddle timing simulation
  wire [3:0] paddle_timer_expired;
  reg paddle_trigger;
  reg [23:0] cpu_cycle_counter;
  
  // Increment cycle counter
  always @(posedge CLK_14M) begin
    if (reset)
      cpu_cycle_counter <= 24'd0;
    else if (phi2)
      cpu_cycle_counter <= cpu_cycle_counter + 24'd1;
  end

  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : paddle_timers
      paddle_timer timer_inst (
        .clk(CLK_14M),
        .reset(reset),
        .trigger(paddle_trigger),
        .paddle_value(paddle_input[i]),
        .cycle_counter(cpu_cycle_counter),
        .timer_expired(paddle_timer_expired[i])
      );
    end
  endgenerate

  // Button merging (physical joystick buttons override keyboard Apple keys)
  // MiSTer joystick bits: [3:0]=directions, [31:4]=action buttons
  wire sw0 = joystick_0[4] | open_apple;    // Open Apple (Button 0)
  wire sw1 = joystick_0[5] | closed_apple;  // Closed Apple (Button 1)
  wire sw2 = joystick_0[6];                 // Button 2  
  //wire sw3 = joystick_0[7];                 // Button 3

// Clock divider instance
clock_divider clk_div_inst (
    .clk_14M(CLK_14M),
    .cyareg(CYAREG),
    .bank(bank),
    .addr(addr),
    .shadow(shadow),
    .IO(IO),
    .reset(reset),
    .stretch(1'b0),  // TODO: Connect to VGC stretch signal
    .clk_14M_en(),
    .clk_7M_en(clk_7M_en),
    .ph0_en(ph0_en),
    .ph2_en(ph2_en),
    .q3_en(q3_en),
    .ph0_state()
);
// Map clock enables to Apple IIgs standard names
assign phi2 = ph2_en;
assign phi0 = ph0_en;
wire ph0_en;
wire ph2_en;
wire clk_7M_en;
assign clk_7M = clk_7M_en;
wire q3_en;

endmodule
