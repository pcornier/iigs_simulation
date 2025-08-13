`timescale 1ns / 100ps

/*
 * Apple IIgs SCC Wrapper
 * 
 * Adapts the existing Mac SCC implementation for Apple IIgs timing and interface
 * 
 * Clock Domain Adaptation:
 * - Mac: 32MHz master -> 8MHz SCC clock (via enables)  
 * - IIgs: 14.32MHz master -> ~3.58MHz SCC clock (divide by 4)
 * 
 * Register Mapping:
 * C038: SCC B Control (Port B Command/Status)
 * C039: SCC A Control (Port A Command/Status) 
 * C03A: SCC B Data (Port B Data)
 * C03B: SCC A Data (Port A Data)
 */

module scc_iigs_wrapper
(
    input               clk_14m,        // 14.32MHz IIgs master clock
    input               ph0_en,
    input               q3_en,
    input               reset,
    
    // IIgs CPU interface  
    input               cs,             // Chip select (C038-C03B range)
    input               we,             // Write enable
    input       [1:0]   rs,             // Register select (addr[1:0])
    input       [7:0]   wdata,          // Write data
    output      [7:0]   rdata,          // Read data
    output              irq_n,          // Interrupt request (active low)
    
    // Serial ports (stubbed for initial implementation)
    output              txd_a,          // Transmit data A (printer port)
    output              txd_b,          // Transmit data B (modem port)  
    input               rxd_a,          // Receive data A
    input               rxd_b,          // Receive data B
    output              rts_a,          // Request to send A
    output              rts_b,          // Request to send B
    input               cts_a,          // Clear to send A  
    input               cts_b           // Clear to send B
);

reg [7:0] out_reg;
assign rdata = out_reg;

// Clock divider: 14.32MHz -> ~1.79MHz (divide by 8) 
// This matches the Apple IIgs PCLK timing used by SCC and DOC systems
// Based on software emulator analysis: PCLK = 14.32MHz/8 ≈ 1.79MHz
reg [2:0] clk_div;
wire scc_clk_en;

always @(posedge clk_14m or posedge reset) begin
    if (reset) begin
        clk_div <= 3'b000;
    end else begin
        clk_div <= clk_div + 1'b1;
    end
end

// Generate clock enable pulses
// Enable every 8th cycle to create ~1.79MHz PCLK timing from 14.32MHz
assign scc_clk_en = (clk_div == 3'b000);

// Address decoding for SCC registers
// rs[1] = 0: Control registers, rs[1] = 1: Data registers  
// rs[0] = 0: Port B, rs[0] = 1: Port A
wire scc_cs = cs;

// Internal SCC interrupt signal (before masking)
wire scc_internal_irq_n;

//`define FAKESERIAL
`ifdef FAKESERIAL

always @(posedge clk_14m) begin
     if (ph0_en)
	case (rs)
      2'b00: begin $display("SCCB CTRL READ");out_reg <= 8'h04; end // Tx buffer empty = 1
      2'b01: begin $display("SCCA CTRL READ");out_reg <= 8'h04; end // Tx buffer empty = 1
      2'b10: begin $display("SCCB DATA READ");out_reg <= 8'h00; end
      2'b11: begin $display("SCCA DATA READ");out_reg <= 8'h00; end
endcase
end

`else
// Instantiate existing SCC with adapted clocking
scc scc_inst (
    .clk(clk_14m),                      // Master clock
    .cep(ph0_en),                   // Positive edge enable  
    .cen(ph0_en),                  // Negative edge enable (inverted)
    .reset_hw(reset),
    
    // Bus interface
    .cs(scc_cs),
    .we(we), 
    .rs(rs),                            // [1] = data(1)/ctl(0), [0] = a_side(1)/b_side(0)
    .wdata(wdata),
    .rdata(rdata),
    ._irq(scc_internal_irq_n),          // Internal SCC interrupt
    
    // Serial connections - stubbed for initial implementation
    // In future, these could connect to actual UART pins
    .rxd(rxd_a),                        // Use port A receive for single port
    .txd(txd_a),                        // Use port A transmit  
    .cts(cts_a),                        // Clear to send from external device
    .rts(rts_a),                        // Request to send to external device
    
    // DCD inputs (used for mouse on real IIgs, stubbed high = carrier detect)
    .dcd_a(1'b1),                       
    .dcd_b(1'b1),
    
    // Write request output (not used in IIgs)
    .wreq()
);
`endif

// For now, duplicate port A signals to port B
assign txd_b = txd_a;
assign rts_b = rts_a;

// Interrupt control: Disable SCC interrupts but allow internal processing
// The issue is that even though SCC registers work, the interrupt timing
// still interferes with the sound system. Keep interrupts disabled but
// ensure the SCC can still process register access properly.
assign irq_n = scc_internal_irq_n;  // Re-enable SCC interrupts

// Add some debug output for initial testing
`ifdef SIMULATION
always @(posedge clk_14m) begin
    if (cs && we) begin
        $display("SCC IIgs: WR %s%s <= %02h", 
                 rs[0] ? "A" : "B",
                 rs[1] ? "DATA" : "CTRL", 
                 wdata);
    end
    if (cs && !we) begin
        $display("SCC IIgs: RD %s%s => %02h",
                 rs[0] ? "A" : "B", 
                 rs[1] ? "DATA" : "CTRL",
                 rdata);
    end
end
`endif

endmodule
