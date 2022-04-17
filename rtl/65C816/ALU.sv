import P65C816_pkg::*;

module ALU
  (
   input [15:0]        L,
   input [15:0]        R,
   input ALUCtrl_r     CTRL,
   input               w16,
   input               BCD,
   input               CI,
   input               VI,
   input               SI,
   output logic        CO,
   output logic        VO,
   output logic        SO,
   output logic        ZO,
   output logic [15:0] RES,
   output logic [15:0] IntR
   );

  logic [15:0]         IntR16;
  logic [7:0]          IntR8;
  logic                CR8;
  logic                CR16;
  logic                CR;
  logic                ZR;
  logic                CIIn;
  logic                ADDIn;
  logic                BCDIn;

  logic [15:0]         AddR;
  logic                AddCO;
  logic                AddVO;
  logic [15:0]         Result16;
  logic [7:0]          Result8;

  always_comb begin
    CR8 = CI;
    CR16 = CI;
    case (CTRL.fstOp)
      3'b000:
        begin
          CR8 = R[7];
          CR16 = R[15];
          IntR8 = {R[6:0], 1'b0};
          IntR16 = {R[14:0], 1'b0};
        end
      3'b001 :
        begin
          CR8 = R[7];
          CR16 = R[15];
          IntR8 = {R[6:0], CI};
          IntR16 = {R[14:0], CI};
        end
      3'b010 :
        begin
          CR8 = R[0];
          CR16 = R[0];
          IntR8 = {1'b0, R[7:1]};
          IntR16 = {1'b0, R[15:1]};
        end
      3'b011 :
        begin
          CR8 = R[0];
          CR16 = R[0];
          IntR8 = {CI, R[7:1]};
          IntR16 = {CI, R[15:1]};
        end
      3'b100 :
        begin
          IntR8 = R[7:0];
          IntR16 = R;
        end
      3'b101 :
        begin
          IntR8 = R[15:8];
          IntR16 = {R[7:0], R[15:8]};
        end
      3'b110 :
        begin
          IntR8 = ((R[7:0]) - 1);
          IntR16 = (R - 1);
        end
      3'b111 :
        begin
          IntR8 = ((R[7:0]) + 1);
          IntR16 = (R + 1);
        end
    endcase
  end

  assign CR = (w16 == 1'b0) ? CR8 : CR16;

  assign CIIn = CR | ~CTRL.secOp[0];
  assign ADDIn = ~CTRL.secOp[2];
  assign BCDIn = BCD & CTRL.secOp[0];


  AddSubBCD AddSub
    (
     .A    (L),
     .B    (R),
     .CI   (CIIn),
     .ADD  (ADDIn),
     .BCD  (BCDIn),
     .w16  (w16),
     .S    (AddR),
     .CO   (AddCO),
     .VO   (AddVO)
     );

  always_comb begin : xhdl0
    logic [7:0]     temp8;
    logic [15:0]    temp16;
    ZR = 1'b0;
    case (CTRL.secOp)
      3'b000 :
        begin
          CO = CR;
          Result8 = L[7:0] | IntR8;
          Result16 = L | IntR16;
        end
      3'b001 :
        begin
          CO = CR;
          Result8 = L[7:0] & IntR8;
          Result16 = L & IntR16;
        end
      3'b010 :
        begin
          CO = CR;
          Result8 = L[7:0] ^ IntR8;
          Result16 = L ^ IntR16;
        end
      3'b011, 3'b110, 3'b111 :
        begin
          CO = AddCO;
          Result8 = AddR[7:0];
          Result16 = AddR;
        end
      3'b100 :
        begin
          CO = CR;
          Result8 = IntR8;
          Result16 = IntR16;
        end
      3'b101 :
        begin
          CO = CR;
          if (CTRL.fc == 1'b0)
            begin
              Result8 = IntR8 & ((~L[7:0]));
              Result16 = IntR16 & ((~L));
            end
          else
            begin
              Result8 = IntR8 | L[7:0];
              Result16 = IntR16 | L;
            end

          temp8 = IntR8 & L[7:0];
          temp16 = IntR16 & L;
          if ((temp8 == 8'h00 & w16 == 1'b0) | (temp16 == 16'h0000 & w16 == 1'b1))
            ZR = 1'b1;
        end
    endcase
  end : xhdl0

  always_comb begin
    VO = VI;
    if (w16 == 1'b0)
      SO = Result8[7];
    else
      SO = Result16[15];
    case (CTRL.secOp)
      3'b001 :
        if (CTRL.fc == 1'b1)
          begin
            if (w16 == 1'b0)
              begin
                VO = IntR8[6];
                SO = IntR8[7];
              end
            else
              begin
                VO = IntR16[14];
                SO = IntR16[15];
              end
          end
      3'b011 :
        VO = AddVO;
      3'b101 :
        SO = SI;
      3'b111 :
        if (CTRL.fc == 1'b1)
          VO = AddVO;
    endcase
  end

  assign ZO = (CTRL.secOp == 3'b101) ? ZR :
              ((w16 == 1'b0 & Result8 == 8'h00) | (w16 == 1'b1 & Result16 == 16'h0000)) ? 1'b1 :
              1'b0;

  assign RES = (w16 == 1'b0) ? {8'h00, Result8} :
               Result16;
  assign IntR = (w16 == 1'b0) ? {8'h00, IntR8} :
                IntR16;

endmodule
