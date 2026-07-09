// TransWarp GS  Xilinx XC2064 (U64) - per-CLB logic, decoded from FPGA_Config bitstream
// Validated decoder (Ken Shirriff reverse.py + karnaugh.js port).
// 64/64 CLBs used; 35 FF + 29 latch; single global clock K.
// WARNING: inter-CLB routing not decoded - A/B/C/D/K per block are unconnected placeholders.
// Each CLB = combinational F/G over its 4 inputs (+ Q feedback), optional K-clocked register.

// ---- CLB AA  (LATCH)  Config X:G Y:F F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_AA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | C | D | B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB AB  (LATCH)  Config X:F Y:G F:B G:B Q:LATCH SET: RES: CLK:K
module clb_AB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = B;
  assign G = B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB AC  (FF)  Config X:G Y:Q F:B:C:Q G:B Q:FF SET: RES: CLK:K
module clb_AC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = B & C | B & Q | !C & Q;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB AD  (LATCH)  Config X:G Y:F F:A:B:D G:A:B:D Q:LATCH SET: RES: CLK:K
module clb_AD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B & !D;
  assign G = !A & !B & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB AE  (LATCH)  Config X:G Y:F F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_AE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | C | D | B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB AF  (FF)  Config X:G Y:Q F:A:B:C:Q Q:FF SET: RES: CLK:K
module clb_AF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | !C & Q | Q & B | !A & C & !B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB AG  (FF)  Config X:Q Y:G F:B G:A:D Q:FF SET: RES: CLK:K
module clb_AG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = B;
  assign G = !A & !D;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB AH  (LATCH)  Config X:F Y:G F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_AH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | C | D | B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB BA  (FF)  Config X:G Y:Q F:A:B:C:Q Q:FF SET: RES: CLK:K
module clb_BA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | C & Q | Q & !B | A & C & B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB BB  (LATCH)  Config X:G Y:F F:B:D G:A:B:D Q:LATCH SET: RES: CLK:K
module clb_BB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & !B & !D;
  assign G = A & !B & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB BC  (LATCH)  Config X:G Y:F F:C:D G:A:B:D Q:LATCH SET: RES: CLK:K
module clb_BC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !C & D;
  assign G = A | B & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB BD  (FF)  Config X:G Y:Q F:A:B:D Q:FF SET: RES: CLK:K
module clb_BD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B & !D;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB BE  (LATCH)  Config X:F Y:G F:A:B:C G:A:B:C Q:LATCH SET: RES: CLK:K
module clb_BE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | B | C;
  assign G = !A & B & !C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB BF  (FF)  Config X:F Y:Q F:A:C:D Q:FF SET: RES: CLK:K
module clb_BF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & C & !D;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB BG  (LATCH)  Config X:F Y:G F:B G:A:C:D Q:LATCH SET: RES: CLK:K
module clb_BG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & !B;
  assign G = !A & C & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB BH  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_BH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C | A & !D | C & !D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB CA  (LATCH)  Config X:F Y:G F:B:C:D G:B Q:LATCH SET: RES: CLK:K
module clb_CA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = C | B & D;
  assign G = B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB CB  (FF)  Config X:Q Y:G F:A:B:C:Q Q:FF SET: RES: CLK:K
module clb_CB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !C & Q | A & C & B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB CC  (FF)  Config X:G Y:Q F:A:C:Q G:B Q:FF SET: RES: CLK:K
module clb_CC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & C | A & Q | !C & Q;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB CD  (LATCH)  Config X:G Y:F F:A:B:D G:B:D Q:LATCH SET: RES: CLK:K
module clb_CD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & B & !D;
  assign G = !B & !B & !D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB CE  (LATCH)  Config X:F Y:G F:A:B:C G:A:B:C Q:LATCH SET: RES: CLK:K
module clb_CE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & B & !C;
  assign G = A & !B & C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB CF  (LATCH)  Config X:F Y:G F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_CF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & C & !D & B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB CG  (LATCH)  Config X:G Y:F F:A:B:C G:A:C Q:LATCH SET: RES: CLK:K
module clb_CG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A | !B | !C;
  assign G = A & !C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB CH  (FF)  Config X:Q Y:G F:A:B G:B Q:FF SET: RES: CLK:K
module clb_CH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | !B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB DA  (FF)  Config X:Q Y:Q F:A:C:Q G:Q Q:FF SET: RES: CLK:K
module clb_DA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & !Q | A & C;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB DB  (LATCH)  Config X:G Y:F F:A:B:C G:A:C:D Q:LATCH SET: RES: CLK:K
module clb_DB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & B & !C;
  assign G = A & !C & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB DC  (LATCH)  Config X:G Y:F F:B:C:D G:B Q:LATCH SET: RES: CLK:K
module clb_DC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & !C & D;
  assign G = B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB DD  (LATCH)  Config X:G Y:F F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_DD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | !C & D & B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB DE  (LATCH)  Config X:F Y:G F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_DE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C & D | A & D & !B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB DF  (FF)  Config X:Q Y:G F:B:C:Q G:A:D Q:FF SET: RES: CLK:K
module clb_DF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & Q | B & C;
  assign G = A | D;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB DG  (FF)  Config X:Q Y:G F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_DG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | A & B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB DH  (FF)  Config X:G Y:Q F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_DH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | A & B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB EA  (FF)  Config X:G Y:Q F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_EA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | A & B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB EB  (FF)  Config X:Q Y:G F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_EB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | A & B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB EC  (FF)  Config X:G Y:Q F:A:B:C:D Q:FF SET: RES: CLK:K
module clb_EC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & C & !D | !A & !D & B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB ED  (FF)  Config X:Q Y:G F:B:C:Q G:B Q:FF SET: RES: CLK:K
module clb_ED (input A,B,C,D,K, output F,G, output reg Q);
  assign F = B & C | B & Q | !C & Q;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB EE  (FF)  Config X:Q Y:G F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_EE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B | A & Q | !B & Q;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB EF  (FF)  Config X:G Y:Q F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_EF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B | A & Q | !B & Q;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB EG  (LATCH)  Config X:G Y:F F:A:B:D G:B Q:LATCH SET: RES: CLK:K
module clb_EG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !D | A & !B;
  assign G = B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB EH  (FF)  Config X:Q Y:G F:B:C:Q G:B Q:FF SET: RES: CLK:K
module clb_EH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & Q | B & C;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB FA  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_FA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & !C | !A & !D | !C & D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB FB  (LATCH)  Config X:F Y:G F:A:B:D G:A:B:C Q:LATCH SET: RES: CLK:K
module clb_FB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B & !D;
  assign G = A & B & !C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB FC  (FF)  Config X:G Y:Q F:A:B:Q G:C:D Q:FF SET: RES: CLK:K
module clb_FC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B | A & Q | !B & Q;
  assign G = !C & !D;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB FD  (LATCH)  Config X:F Y:G F:A:C:D G:A:B:C Q:LATCH SET: RES: CLK:K
module clb_FD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & C & D;
  assign G = A & B & C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB FE  (FF)  Config X:G Y:Q F:A:B:Q G:A:C Q:FF SET: RES: CLK:K
module clb_FE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & B | A & Q | !B & Q;
  assign G = !A & !C | A & C;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB FF  (FF)  Config X:Q Y:G F:A:B:C:Q Q:FF SET: RES: CLK:K
module clb_FF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | C & Q | Q & B | A & !C & B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB FG  (FF)  Config X:Q Y:G F:B:C:Q G:A:Q Q:FF SET: RES: CLK:K
module clb_FG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & Q | B & C;
  assign G = !A | !Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB FH  (LATCH)  Config X:F Y:G F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_FH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A | !C | !D | !B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB GA  (LATCH)  Config X:F Y:G F:B:C G:A:C Q:LATCH SET: RES: CLK:K
module clb_GA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = B & !C;
  assign G = A & !C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB GB  (LATCH)  Config X:G Y:F F:A:B:D G:A:C:D Q:LATCH SET: RES: CLK:K
module clb_GB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A | B & D;
  assign G = A | C & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB GC  (LATCH)  Config X:G Y:F F:B:D G:B:C Q:LATCH SET: RES: CLK:K
module clb_GC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & !D;
  assign G = !B & !C;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB GD  (LATCH)  Config X:G Y:F F:A:B:C G:B Q:LATCH SET: RES: CLK:K
module clb_GD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = B | A & C;
  assign G = B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB GE  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_GE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & C | A & D | !C & D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB GF  (LATCH)  Config X:F Y:G F:A:B:C G:B Q:LATCH SET: RES: CLK:K
module clb_GF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A | !B | !C;
  assign G = B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB GG  (FF)  Config X:G Y:Q F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_GG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | A & B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB GH  (LATCH)  Config X:F Y:G F:A:B:C:D Q:LATCH SET: RES: CLK:K
module clb_GH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C | A & !B | !C & !D | !D & !B;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB HA  (LATCH)  Config X:F Y:G F:A:C G:A:C:D Q:LATCH SET: RES: CLK:K
module clb_HA (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & C;
  assign G = A & C & D;
  always @(*) if (K) Q <= F;    // transparent latch
endmodule

// ---- CLB HB  (FF)  Config X:Q Y:G F:B:C:Q G:B Q:FF SET: RES: CLK:K
module clb_HB (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !B & Q | B & C;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB HC  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_HC (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C | A & D | C & D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB HD  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_HD (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C | A & D | C & D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB HE  (FF)  Config X:G Y:Q F:A:B:Q G:B Q:FF SET: RES: CLK:K
module clb_HE (input A,B,C,D,K, output F,G, output reg Q);
  assign F = !A & Q | A & B;
  assign G = B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB HF  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_HF (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C | A & !D | C & !D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB HG  (FF)  Config X:Q Y:Q F:A:C:D G:Q Q:FF SET: RES: CLK:K
module clb_HG (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & !C | A & D | C & D;
  assign G = Q;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

// ---- CLB HH  (FF)  Config X:Q Y:G F:A:B:C:Q Q:FF SET: RES: CLK:K
module clb_HH (input A,B,C,D,K, output F,G, output reg Q);
  assign F = A & Q | C & Q | Q & !B | !A & C & B;
  always @(posedge K) Q <= F;   // FF (Q source per X/Y mux; routing undecoded)
endmodule

