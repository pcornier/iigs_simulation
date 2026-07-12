// ============================================================================
// twgs_nvram.sv — Xicor X2444 serial NVRAM model for the TransWarp GS
//
// The card's settings NVRAM (U37, X2444P): 16 words x 16 bits, accessed
// bit-serially through two card registers:
//   $BC4001  TWGS_Serial_Control : bit7 = chip-select (CE), bit0 = read dir
//   $BC4000  TWGS_Serial_Data    : one serial bit clocked per CPU access,
//                                   MSB-first. DI = write-data bit7 (on a
//                                   store), DO = read-data bit7 (on a load).
//
// Protocol reverse-engineered from the ROM's own primitives
// (TransWarpGS-ROM src/twgs_1.8s/twgs.s:255-344):
//
//   NVRAM_Send_Byte : CE=1, then 8 stores to $BC4000 shift a byte in, MSB1st.
//   command byte    = [1][addr3:0][op2:0]  (start bit + 4-bit addr + 3-bit op)
//        op 011 = WRITE-RAM (then 16 data bits: low byte, then high byte)
//        op 110 = READ-RAM  (then master reads 16 bits: low byte, then high)
//        op 100 = WREN,  000 = WRDI,  001 = STORE,  101 = RECALL
//   NVRAM_Read_Word uses NVRAM_Send_Cmd_and_Read, which sends the top 7 command
//   bits in write mode then FORCES the 8th (lsb) bit to 1 while switching to
//   read mode (twgs.s:269-283). So a READ command lands here as op 111, not
//   110 — we decode 111 as READ. (Writes use a clean 8-bit send -> op 011.)
//
// STORE/RECALL are no-ops: this model's array IS the persistent store (there is
// no separate RAM/EEPROM shadow). Pre-seeded at power-on with a VALID config so
// the TWGS ROM's boot path short-circuits (word6=$AE => skip all diagnostics /
// intro, twgs.s:638 NVRAM_Active_Check) and the jump-table speed queries
// (GetMaxSpeed etc.) return a sane value WITHOUT the boot ROM ever running.
//
// Clock-enable friendly. data_stb / ctrl_wr_stb must be ONE pulse per CPU
// access to $BC4000 / $BC4001 respectively (gate with phi2 in the caller).
// ============================================================================

module twgs_nvram (
    input  wire       clk,            // CLK_14M
    input  wire       reset,

    // $BC4001 write (control): captures CE (bit7) and direction (bit0)
    input  wire       ctrl_wr_stb,
    input  wire [7:0] ctrl_wr_data,

    // $BC4000 access: one serial-bit clock. data_we=1 for a store (DI valid on
    // data_wr_data[7]), data_we=0 for a load (returns DO on data_dout[7]).
    input  wire       data_stb,
    input  wire       data_we,
    input  wire [7:0] data_wr_data,

    output wire [7:0] data_dout,       // $BC4000 read value ({DO,7'b0})

    // NVRAM backup port (MiSTer SD save/load): byte view of the 16x16-bit
    // store, little-endian per word (byte 2i = word i low byte, 2i+1 = high).
    input  wire [4:0] bk_addr,
    input  wire       bk_wr,
    input  wire [7:0] bk_data,
    output wire [7:0] bk_q,

    // Host (OSD) views of the TWGS_Config_Byte startup bits (NVRAM word 2:
    // bit2 = Startup Graphics, bit3 = Startup Sound -- twgs.3.s:580 checks
    // #$0004; default config $0D has both set). Edge-applied like every other
    // shared setting; the firmware/CDA writing NVRAM mirrors back via the
    // gfx_en/snd_en outputs.
    input  wire       host_gfx_en,
    input  wire       host_snd_en,
    output wire       gfx_en,
    output wire       snd_en
);

  // ---- 16 x 16-bit store ---------------------------------------------------
  // Powers up ZERO = INVALID (word0 magic != $AE). With the Tier C reset
  // overlay the firmware itself initializes NVRAM on first boot (diagnostics +
  // startup intro + speed measurement -> NVRAM_Validate writes the $AE magic),
  // and the MiSTer NVRAM save slot persists it from then on. The old Tier B
  // pre-seed (which existed to short-circuit a boot that could never run) is
  // obsolete.
  reg [15:0] mem [0:15];
  integer i;
  initial begin
    for (i = 0; i < 16; i = i + 1) mem[i] = 16'h0000;
  end

  localparam [1:0] S_IDLE = 2'd0, S_CMD = 2'd1, S_WR = 2'd2, S_RD = 2'd3;

  reg [1:0]  state;
  reg        ce;              // chip select (control bit7)
  reg        rd_dir;          // control bit0 (1 = FPGA readback direction)
  reg        we_en;           // write-enable latch (WREN/WRDI)
  reg [7:0]  cmd;             // command shift-in
  reg [3:0]  bitcnt;          // command bit counter (0..8)
  reg [3:0]  addr;            // selected word
  reg [15:0] wbuf;            // write data shift-in (low byte first, MSB1st)
  reg [4:0]  datacnt;         // data bit counter (0..16)
  reg [7:0]  shiftout;        // read data shift-out (current byte, MSB1st)
  reg        gfx_prev, snd_prev;

  // Read data: drive DO while actively reading NVRAM. In FPGA-readback mode
  // ($BC4001=$01: CE=0, bit0=1) return DO stuck HIGH ($80): the firmware's
  // frame assembler inverts the bits (EOR #$FF), so constant-1 reads produce a
  // $00 frame whose stop bit is CLEAR -> FPGA_Init_Readback returns carry
  // clear and the boot SKIPS FPGA_Check_Readback (constant-0 reads assemble
  // to $FF frames with a "valid" stop bit and the checker runs -> error 0001).
  assign data_dout = (state == S_RD && ce) ? {shiftout[7], 7'h00} :
                     (!ce && rd_dir)       ? 8'h80 : 8'h00;

  // Full 8-bit command as of the 8th (last) command bit: the 7 bits already in
  // `cmd` plus the bit arriving this cycle. op = [2:0], addr = [6:3].
  wire [7:0] cmd_final = {cmd[6:0], data_wr_data[7]};

  always @(posedge clk) begin
    if (reset) begin
      state <= S_IDLE; ce <= 1'b0; we_en <= 1'b0; rd_dir <= 1'b0;
      gfx_prev <= 1'b1; snd_prev <= 1'b1;   // match the OSD defaults (On)
      cmd <= 8'h00; bitcnt <= 4'd0; addr <= 4'd0;
      wbuf <= 16'h0000; datacnt <= 5'd0; shiftout <= 8'h00;
    end else begin
      // ---- control write: chip-select edge starts a transaction ----------
      if (ctrl_wr_stb) begin
        if (ctrl_wr_data[7] && !ce) begin      // CE rising: begin new command
          state <= S_CMD; bitcnt <= 4'd0; cmd <= 8'h00;
        end else if (!ctrl_wr_data[7]) begin   // CE low: end transaction
          state <= S_IDLE;
        end
        ce     <= ctrl_wr_data[7];
        rd_dir <= ctrl_wr_data[0];
      end

      // ---- serial bit clock on each $BC4000 access -----------------------
      if (data_stb && (ctrl_wr_stb ? ctrl_wr_data[7] : ce)) begin
        case (state)
          // -------- shift in the 8-bit command --------------------------
          S_CMD: begin
            cmd    <= {cmd[6:0], data_wr_data[7]};
            bitcnt <= bitcnt + 4'd1;
            if (bitcnt == 4'd7) begin
              // command complete this cycle; decode from the fully-formed value
              addr <= cmd_final[6:3];
              case (cmd_final[2:0])
                3'b011: begin state <= S_WR; datacnt <= 5'd0;              end // WRITE
                3'b111: begin state <= S_RD; datacnt <= 5'd0;                 // READ (lsb forced to 1)
                              shiftout <= mem[cmd_final[6:3]][7:0]; end
                3'b100: begin we_en <= 1'b1; state <= S_IDLE;             end // WREN
                3'b000: begin we_en <= 1'b0; state <= S_IDLE;             end // WRDI
                default:      state <= S_IDLE;                                // STORE/RECALL: no-op
              endcase
            end
          end
          // -------- shift in write data: low byte then high byte --------
          S_WR: begin
            wbuf    <= {wbuf[14:0], data_wr_data[7]};
            datacnt <= datacnt + 5'd1;
            if (datacnt == 5'd15) begin
              // Include the bit arriving THIS access: wbuf has only 15 bits
              // shifted in when the 16th lands (committing plain wbuf stored
              // every word right-shifted by one -- $FFFF read back as $7FFF,
              // caught by the firmware's own Test_NVRAM).
              if (we_en)
                mem[addr] <= {wbuf[6:0], data_wr_data[7], wbuf[14:7]}; // {high, low}
              state <= S_IDLE;
            end
          end
          // -------- shift out read data: low byte then high byte --------
          S_RD: begin
            if (datacnt == 5'd7) begin
              shiftout <= mem[addr][15:8];   // reload high byte after low byte
              datacnt  <= 5'd8;
            end else begin
              shiftout <= {shiftout[6:0], 1'b0};
              datacnt  <= datacnt + 5'd1;
            end
          end
          default: ;
        endcase
      end

      // OSD startup-bit toggles: edge-apply into the config word.
      gfx_prev <= host_gfx_en;
      snd_prev <= host_snd_en;
      if (host_gfx_en != gfx_prev) mem[2][2] <= host_gfx_en;
      if (host_snd_en != snd_prev) mem[2][3] <= host_snd_en;

      // Backup load (SD -> mem): last in the block so it wins over a
      // same-cycle serial write (loads happen at mount/OSD time).
      if (bk_wr) begin
        if (bk_addr[0]) mem[bk_addr[4:1]][15:8] <= bk_data;
        else            mem[bk_addr[4:1]][7:0]  <= bk_data;
      end
    end
  end

  assign bk_q = bk_addr[0] ? mem[bk_addr[4:1]][15:8] : mem[bk_addr[4:1]][7:0];
  assign gfx_en = mem[2][2];
  assign snd_en = mem[2][3];

  // Only bit7 of the control/data write matters (CE / serial DI, MSB-first);
  // data_we is informational. Sink the rest to keep strict lint quiet.
  wire _unused = &{1'b0, data_we, ctrl_wr_data[6:0], data_wr_data[6:0], cmd[7]};

`ifdef VERILATOR
  always @(posedge clk) begin
    if (!reset && data_stb && state == S_CMD && bitcnt == 4'd7)
      $display("TWGS-NVRAM: cmd=%02x op=%b addr=%0d mem=%04x",
               cmd_final, cmd_final[2:0], cmd_final[6:3], mem[cmd_final[6:3]]);
    if (!reset && data_stb && state == S_WR && datacnt == 5'd15)
      $display("TWGS-NVRAM: WRITE addr=%0d val=%04x we_en=%0d",
               addr, {wbuf[6:0], data_wr_data[7], wbuf[14:7]}, we_en);
  end
`endif

endmodule
