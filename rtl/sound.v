`timescale 1ns/1ns

module sound
   (input             CLK_14M,
    input             clk_7M_en,
    input             ph0_en,
    input             select,
    input             reset,
    input             wr,
    input [1:0]       host_addr,
    input [7:0]       host_data_in,
    output [7:0]      host_data_out,
    output reg [15:0] sound_out,
    output reg        out_strobe,
    output [3:0]      ca,
    output            irq,
    // Apple II speaker input
    input             speaker_state);

   wire [16:0]       doc_addr_out;
   wire [15:0]       ram_addr;
   wire [15:0]       glu_addr_out;
   wire [7:0]        glu_data_in;
   wire [7:0]        glu_data_out;
   wire [7:0]        ram_data_out;
   wire [7:0]        doc_data_out;
   wire              doc_host_en;
   wire              sound_wr;
   wire              ram_wr;
   wire              doc_wr;
   wire              ram_select;
   wire              osc_en;
   wire [15:0]       doc_sound_out;

   assign glu_data_in = ram_select ? ram_data_out : doc_data_out;
   assign ram_addr    = osc_en ? doc_addr_out[15:0] : glu_addr_out;

   // Speaker audio: +/- 8192 centered around 0
   wire signed [15:0] speaker_audio = speaker_state ? 16'sh2000 : -16'sh2000;

   // Boost DOC output by 4x (<<2) and mix with speaker
   wire signed [15:0] doc_boosted = doc_sound_out <<< 2;

   always @(posedge CLK_14M) begin
      out_strobe <= osc_en;
      // Mix boosted DOC with speaker audio
      sound_out  <= doc_boosted + speaker_audio;
   end

   // BUGFIX: forward ph0_en into soundglu so doc_enable is clocked correctly
   soundglu glu
     (.CLK_14M(CLK_14M),
      .clk_7M_en(clk_7M_en),
      .ph0_en(ph0_en),
      .reset(reset),
      .select(select),
      .wr(wr),
      .host_addr(host_addr),
      .host_data_in(host_data_in),
      .sound_data_in(glu_data_in),
      .osc_en(osc_en),
      .ram_access(ram_select),
      .host_data_out(host_data_out),
      .sound_addr(glu_addr_out),
      .sound_data_out(glu_data_out),
      .ram_wr(ram_wr),
      .doc_wr(doc_wr),
      .doc_host_en(doc_host_en));

   syncram ram(
      .clk(CLK_14M),
      .we(ram_wr),
      .data_in(glu_data_out),
      .addr(ram_addr),
      .data_out(ram_data_out));

   es5503 doc(
      .CLK_14M(CLK_14M),
      .clk_7M_en(clk_7M_en),
      .reset(reset),
      .wr(doc_wr),
      .host_en(doc_host_en),
      .reg_addr(glu_addr_out[7:0]),
      .reg_data_in(glu_data_out),
      .sample_data_in(ram_data_out),
      .data_out(doc_data_out),
      .addr_out(doc_addr_out),
      .sound_out(doc_sound_out),
      .ca(ca),
      .irq(irq),
      .osc_en(osc_en));
endmodule
