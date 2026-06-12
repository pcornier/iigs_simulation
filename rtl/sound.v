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
    output [15:0]     sound_out_l,
    output [15:0]     sound_out_r,
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
   wire [15:0]       iir_sound_out_l;
   wire [15:0]       iir_sound_out_r;

   assign glu_data_in = ram_select ? ram_data_out : doc_data_out;
   assign ram_addr    = osc_en ? doc_addr_out[15:0] : glu_addr_out;

   wire signed [15:0] iir_boosted_l = iir_sound_out_l <<< 2;
   wire signed [15:0] iir_boosted_r = iir_sound_out_r <<< 2;

   // TODO: Better speaker click modeling; for now just toggle a bit like the IIe core
   wire signed [15:0] speaker_audio = speaker_state ? 16'sh0800 : -16'h0800;

   assign sound_out_l = iir_boosted_l + speaker_audio;
   assign sound_out_r = iir_boosted_r + speaker_audio;

   reg [15:0] doc_sound_l;
   reg [15:0] doc_sound_r;

   // Demux stereo
   always @(posedge CLK_14M) if (osc_en) begin
      doc_sound_l <= ca[0] ? doc_sound_out : 16'd0;
      doc_sound_r <= ca[0] ? 16'd0 : doc_sound_out;
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

   // In stereo mode, the filter needs to run two cycles per sample period
   reg osc_en_d;
   wire iir_ce = osc_en | osc_en_d;

   always @(posedge CLK_14M) osc_en_d <= osc_en;

   // 10khz 1st + AA, fs=894886
   IIR_filter
     #(
       .use_params(1),
       .stereo(1),
       .coeff_x (0.00138604585989953941),
       .coeff_x0(3),
       .coeff_x1(3),
       .coeff_x2(1),
       .coeff_y0(-2.79476671867831694129),
       .coeff_y1( 2.61357669738641673618),
       .coeff_y2(-0.81781102634857016920))
   psg_iir
     (
      .clk(CLK_14M),
      .reset(reset),

      .ce(iir_ce),
      .sample_ce(1),

      .input_l(doc_sound_l),
      .input_r(doc_sound_r),
      .output_l(iir_sound_out_l),
      .output_r(iir_sound_out_r));

endmodule
