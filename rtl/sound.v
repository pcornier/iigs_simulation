`timescale 1ns/1ns

`ifdef SOUND_STUB
// Minimal stub for the IIgs sound interface that:
// - Accepts host reads/writes (SNDCTL/SNDDATA/SNDAPL/SNDAPH)
// - Implements auto-increment of address pointer
// - Always deasserts IRQ and produces no audio
// - Adds debug $display messages for tracing
module sound
   (input        CLK_14M,
    input        ph0_en,
    input        select,
    input        reset,
    input        wr,
    input [1:0]  host_addr,
    input [7:0]  host_data_in,
    output reg [7:0] host_data_out,
    output reg [15:0] sound_out,
    output reg        out_strobe,
    output [3:0]      ca,
   output            irq);

   // Host-visible state
   reg        ram_access;       // 1 = access RAM, 0 = DOC regs
   reg        auto_increment;   // auto-inc address pointer on accesses
   reg [3:0]  volume;
   reg [15:0] sound_addr;       // address pointer
   reg [7:0]  read_data_reg;    // latched read data
   reg        select_d;         // strobe edge detect

   // Simple 256-byte scratch area for read-back when RAM mode
   // (enough to avoid X-prop in logs and allow basic tests)
   reg [7:0]  scratch [0:255];

   // IRQ/audio are not used in stub
   assign ca  = 4'b0000;
   assign irq = 1'b0;

   // Quick banner so logs confirm we’re in stub mode
   initial $display("%m: SOUND_STUB active (no IRQ, silent audio)");

   // Drive muted audio and a simple out_strobe so downstream doesn’t see X
   always @(posedge CLK_14M) begin
      sound_out  <= 16'h0000;
      out_strobe <= ph0_en;  // Arbitrary, keep timing consistent
   end

   // Host register interface, emulating soundglu’s behavior
   always @(posedge CLK_14M) begin
      if (reset) begin
         ram_access      <= 1'b0;
         auto_increment  <= 1'b0;
         volume          <= 4'h0;
         sound_addr      <= 16'h0000;
         read_data_reg   <= 8'h00;
         select_d        <= 1'b0;
         host_data_out   <= 8'h00;
      end else begin
         select_d <= select;

         if (!select_d && select) begin
            if (wr) begin
               case (host_addr)
                 2'd0: begin // SNDCTL
                    ram_access     <= host_data_in[6];
                    auto_increment <= host_data_in[5];
                    volume         <= host_data_in[3:0];
                    $display("%m: STUB SNDCTL <= %02h  (ram=%0d ai=%0d vol=%0h)", host_data_in, host_data_in[6], host_data_in[5], host_data_in[3:0]);
                 end
                 2'd1: begin // SNDDATA
                    // In RAM mode, write to a tiny scratch area for visibility
                    if (ram_access) begin
                       scratch[sound_addr[7:0]] <= host_data_in;
                       $display("%m: STUB RAM[%04h] <= %02h", sound_addr, host_data_in);
                    end else begin
                       // DOC register write (ignored in stub)
                       $display("%m: STUB DOC[%02h] <= %02h (ignored)", sound_addr[7:0], host_data_in);
                    end
                    if (auto_increment)
                      sound_addr <= sound_addr + 16'd1;
                 end
                 2'd2: begin // SNDAPL
                    sound_addr[7:0] <= host_data_in;
                    $display("%m: STUB APL  <= %02h  -> addr=%04h", host_data_in, {sound_addr[15:8], host_data_in});
                 end
                 2'd3: begin // SNDAPH
                    sound_addr[15:8] <= host_data_in;
                    $display("%m: STUB APH  <= %02h  -> addr=%04h", host_data_in, {host_data_in, sound_addr[7:0]});
                 end
               endcase
            end else begin
               case (host_addr)
                 2'd0: begin // SNDCTL readback
                    host_data_out <= {1'b0, ram_access, auto_increment, 1'b1, volume};
                    $display("%m: STUB SNDCTL -> %02h", host_data_out);
                 end
                 2'd1: begin // SNDDATA read
                    if (ram_access) begin
                      host_data_out <= scratch[sound_addr[7:0]];
                      $display("%m: STUB RAM[%04h] -> %02h", sound_addr, host_data_out);
                    end else begin
                      // Minimal DOC register semantics: return OIR as 'no pending'
                      // and sensible defaults for others to avoid OS warnings.
                      case (sound_addr[7:0])
                        8'hE0: begin // OIR: no interrupts pending (use E1 pattern)
                          host_data_out <= 8'hE1;
                          $display("%m: STUB DOC[OIR E0] -> %02h (no pending)", host_data_out);
                        end
                        8'hE1: begin // Oscillator Enable Register
                          host_data_out <= 8'h00;
                          $display("%m: STUB DOC[EN E1] -> %02h", host_data_out);
                        end
                        default: begin
                          host_data_out <= 8'h00;
                          $display("%m: STUB DOC[%02h] -> %02h", sound_addr[7:0], host_data_out);
                        end
                      endcase
                    end
                    if (auto_increment)
                      sound_addr <= sound_addr + 16'd1;
                 end
                 2'd2: begin // SNDAPL
                    host_data_out <= sound_addr[7:0];
                    $display("%m: STUB APL  -> %02h", sound_addr[7:0]);
                 end
                 2'd3: begin // SNDAPH
                    host_data_out <= sound_addr[15:8];
                    $display("%m: STUB APH  -> %02h", sound_addr[15:8]);
                 end
               endcase
            end
         end
      end
   end
endmodule
`else

module sound
   (input        CLK_14M,
    input        ph0_en,
    input        select,
    input        reset,
    input        wr,
    input [1:0]  host_addr,
    input [7:0]  host_data_in,
    output [7:0] host_data_out,
    output reg [15:0] sound_out,
    output reg        out_strobe,
    output [3:0]      ca,
   output            irq);

   wire [16:0]       doc_addr_out;
   wire [15:0]       ram_addr;
   wire [15:0]       glu_addr_out;
   wire [7:0]        glu_data_in;
   wire [7:0]        glu_data_out;
   wire [7:0]        ram_data_out;
   wire [7:0]        doc_data_out;
   wire              sound_wr;
   wire              ram_wr;
   wire              doc_wr;
   wire              ram_select;
   wire              osc_en;
   wire [15:0]       doc_sound_out;

   reg [7:0]         doc_sample;
   reg               osc_en_d;

   assign glu_data_in = ram_select ? ram_data_out : doc_data_out;
   assign ram_addr    = osc_en ? doc_addr_out[15:0] : glu_addr_out;

   always @(posedge CLK_14M) begin
      out_strobe <= osc_en;
      sound_out  <= doc_sound_out;
      osc_en_d   <= osc_en;
      if (osc_en_d && !osc_en)
        doc_sample <= ram_data_out;
   end

   // BUGFIX: forward ph0_en into soundglu so doc_enable is clocked correctly
   soundglu glu
     (.clk(CLK_14M),
      .ph0_en(ph0_en),
      .reset(reset),
      .select(select),
      .wr(wr),
      .host_addr(host_addr),
      .host_data_in(host_data_in),
      .sound_data_in(glu_data_in),
      .ram_access(ram_select),
      .host_data_out(host_data_out),
      .sound_addr(glu_addr_out),
      .sound_data_out(glu_data_out),
      .ram_wr(ram_wr),
      .doc_wr(doc_wr),
      .doc_enable(osc_en));

   syncram ram(
      .clk(CLK_14M),
      .we(ram_wr),
      .data_in(glu_data_out),
      .addr(ram_addr),
      .data_out(ram_data_out));

   es5503 doc(
      .clk(CLK_14M),
      .osc_en(osc_en),
      .reset(reset),
      .wr(doc_wr),
      .reg_addr(glu_addr_out[7:0]),
      .reg_data_in(glu_data_out),
      .sample_data_in(doc_sample),
      .data_out(doc_data_out),
      .addr_out(doc_addr_out),
      .sound_out(doc_sound_out),
      .ca(ca),
      .irq(irq));

   // Banner to confirm full DOC path is built
   initial $display("%m: SOUND full DOC path active");

endmodule
`endif
