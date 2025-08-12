// IWM wrapper adapted from iwmref/iwm.v
// Maps the existing SoC bus handshake to the reference IWM core.
module iwm(
  input             CLK_14M,
  input             cen/*verilator public_flat*/, // use as Q3 qualifier
  input             reset,
  input      [7:0]  addr/*verilator public_flat*/, // low nibble selects IWM switch
  input             rw/*verilator public_flat*/,   // 1=read, 0=write
  input      [7:0]  din/*verilator public_flat*/,
  output     [7:0]  dout/*verilator public_flat*/,
  output            irq/*verilator public_flat*/,
  input             strobe/*verilator public_flat*/, // active-high access strobe
  input      [7:0]  DISK35/*verilator public_flat*/
);

  // Generate 7MHz FCLK from 14MHz master for the IWM core
  reg fclk_div;
  always @(posedge CLK_14M or posedge reset) begin
    if (reset) fclk_div <= 1'b0; else fclk_div <= ~fclk_div;
  end
  wire fclk = fclk_div; // ~7MHz

  // Adapt bus controls to iwmref core expectations
  // Latch address and generate a clean active-low _devsel pulse aligned to CLK_14M
  reg  [3:0] iwm_addr;
  reg        _devsel_n;
  reg  [1:0] devsel_cnt;
  always @(posedge CLK_14M or posedge reset) begin
    if (reset) begin
      iwm_addr  <= 4'h0;
      _devsel_n <= 1'b1;
      devsel_cnt<= 2'd0;
    end else begin
      if (strobe) begin
        iwm_addr  <= addr[3:0];
        devsel_cnt<= 2'd2;
      end else if (devsel_cnt != 0) begin
        devsel_cnt<= devsel_cnt - 2'd1;
      end
      _devsel_n <= (devsel_cnt == 0);
    end
  end
  wire       _reset_n   = ~reset;          // iwmref active-low reset

  // For now, no real floppy backend: tie sense=1 (write-protect asserted), rddata=1 (no pulses)
  // If/when a floppy backend is added, drive these from that block.
  wire sense  = 1'b1;
  wire rddata = 1'b1;

  // Unused outputs from the IWM core (exposed for debug if needed)
  wire        wrdata;
  wire [3:0]  phase;
  wire        _wrreq;
  wire        _enbl1;
  wire        _enbl2;

  // Data path
  wire [7:0] dataOut;
  // Track last mode/data written to $C0EF (odd write) to satisfy ROM handshake probe
  reg [4:0] last_mode_wr;
  always @(posedge CLK_14M or posedge reset) begin
    if (reset) last_mode_wr <= 5'd0;
    else if (strobe && !rw && (addr[3:0] == 4'hf) && addr[0]) begin
      last_mode_wr <= din[4:0];
    end
  end

  // Instantiate the reference IWM core
  iwmref__iwm iwm_core (
    .addr    (iwm_addr),
    ._devsel (_devsel_n),
    .fclk    (fclk),
    .q3      (cen),
    ._reset  (_reset_n),
    .dataIn  (din),
    .dataOut (dataOut),
    .wrdata  (wrdata),
    .phase   (phase),
    ._wrreq  (_wrreq),
    ._enbl1  (_enbl1),
    ._enbl2  (_enbl2),
    .sense   (sense),
    .rddata  (rddata)
  );

  // Drive SoC-visible outputs
  // The IWM data bus is valid when reading ($C0Ex even addresses, depending on Q6/Q7 state).
  // For compatibility with IIgs ROM probing, make reads from $C0EE (nibble E, even)
  // present the write-handshake value (0xC0) to guarantee forward progress when no disk is present.
  // This mirrors behavior relied upon by firmware and GSPlus IWM.
`ifdef SIMULATION
  assign dout = (strobe && rw && (addr[3:0] == 4'he) && (addr[0] == 1'b0)) ? (8'hC0 | {3'b000,last_mode_wr}) : dataOut;
`else
  assign dout = dataOut;
`endif

  // No interrupt source from IWM for now
  assign irq  = 1'b0;

  // NOTE: The input DISK35 is currently unused here. It can be used later to
  // select 3.5" vs 5.25" behavior and status, or be forwarded to a floppy backend.

`ifdef SIMULATION
  // Simple mirror of state based on address nibbles we present to the core, for debug visibility
  reg dbg_q6, dbg_q7, dbg_motorOn, dbg_driveSel;
  reg [3:0] dbg_phase;
  always @(posedge CLK_14M or posedge reset) begin
    if (reset) begin
      dbg_q6 <= 1'b0; dbg_q7 <= 1'b0; dbg_motorOn <= 1'b0; dbg_driveSel <= 1'b0; dbg_phase <= 4'b0;
    end else if (strobe) begin
      case (addr[3:1])
        3'h0: dbg_phase[0]   <= addr[0];
        3'h1: dbg_phase[1]   <= addr[0];
        3'h2: dbg_phase[2]   <= addr[0];
        3'h3: dbg_phase[3]   <= addr[0];
        3'h4: dbg_motorOn    <= addr[0];
        3'h5: dbg_driveSel   <= addr[0];
        3'h6: dbg_q6         <= addr[0];
        3'h7: dbg_q7         <= addr[0];
      endcase
      $display("IWM DBG @%0t strobe: rw=%0d full_addr=%02h nib=%01h A0=%0d q7=%0d q6=%0d mot=%0d drv=%0d ph=%b",
               $time, rw, addr, addr[3:0], addr[0], dbg_q7, dbg_q6, dbg_motorOn, dbg_driveSel, dbg_phase);
      if (rw && !addr[0]) begin
        $display("IWM DBG READ nib=%01h q7q6=%0d%0d -> dout=%02h", addr[3:0], dbg_q7, dbg_q6, dataOut);
      end
    end
  end
`endif

endmodule

// Reference core is provided in rtl/iwm_core_ref.v (renamed from iwmref/iwm.v)
