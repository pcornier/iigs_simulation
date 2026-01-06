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
    output [15:0]     sound_out,
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
   wire [15:0]       iir_sound_out;

   assign glu_data_in = ram_select ? ram_data_out : doc_data_out;
   assign ram_addr    = osc_en ? doc_addr_out[15:0] : glu_addr_out;

   wire signed [15:0] iir_boosted = iir_sound_out <<< 2;
   assign sound_out = iir_boosted;

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

   // TODO: This filter is from the MegaDrive core. Should be
   // reasonable for modeling the internal speaker in mono, but needs
   // to be replaced with a more LiteSound-like filter for stereo.

   //  8KHz 2tap
   IIR_filter
     #(
       .use_params(1),
       .stereo(0),
       .coeff_x (0.0000943),
       .coeff_x0(2),
       .coeff_x1(1),
       .coeff_x2(0),
       .coeff_y0(-1.98992552008492529225),
       .coeff_y1( 0.98997601394542067421),
       .coeff_y2(0))
   psg_iir
     (
      .clk(CLK_14M),
      .reset(reset),

      .ce(osc_en),
      .sample_ce(1),

      .input_l(doc_sound_out),
      .output_l(iir_sound_out));

endmodule
