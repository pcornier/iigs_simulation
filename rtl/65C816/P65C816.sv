import P65C816_pkg::*;

module P65C816
  (
   input         CLK/*verilator public_flat*/,
   input         RST_N,
   input         CE,

   input         RDY_IN,
   input         NMI_N,
   input         IRQ_N/*verilator public_flat*/,
   input         ABORT_N,
   input [7:0]   D_IN/*verilator public_flat*/,
   output [7:0]  D_OUT/*verilator public_flat*/,
   output [23:0] A_OUT/*verilator public_flat*/,
   output logic  WE/*verilator public_flat*/,
   output logic  RDY_OUT,
   output logic  VPA/*verilator public_flat*/,
   output logic  VDA/*verilator public_flat*/,
   output logic  MLB/*verilator public_flat*/,
   output logic  VPB/*verilator public_flat*/
   );

  logic [15:0]   A/*verilator public_flat*/;
  logic [15:0]   X/*verilator public_flat*/;
  logic [15:0]   Y/*verilator public_flat*/;
  logic [15:0]   D/*verilator public_flat*/;
  logic [15:0]   SP/*verilator public_flat*/;
  logic [15:0]   T/*verilator public_flat*/;
  logic [7:0]    PBR/*verilator public_flat*/;
  logic [7:0]    DBR/*verilator public_flat*/;
  logic [8:0]    P/*verilator public_flat*/;
  logic [15:0]   PC/*verilator public_flat*/;

  logic [7:0]    DR;
  logic          EF;
  logic          XF;
  logic          MF;
  logic          oldXF;
  logic [15:0]   SB;
  logic [15:0]   DB;
  logic          EN;
  MCode_r          MC;
  logic [7:0]    IR/*verilator public_flat*/;
  logic [7:0]    NextIR;
  logic [3:0]    STATE;
  logic [3:0]    NextState;
  logic          LAST_CYCLE;
  logic          GotInterrupt;
  logic          IsResetInterrupt;
  logic          IsNMIInterrupt;
  logic          IsIRQInterrupt;
  logic          IsABORTInterrupt;
  logic          IsBRKInterrupt;
  logic          IsCOPInterrupt;
  logic          JumpTaken;
  logic          JumpNoOverflow;
  logic          IsBranchCycle1;
  logic          w16;
  logic          DLNoZero;
  logic          WAIExec;
  logic          STPExec;
  logic          NMI_SYNC;
  logic          NMI_ACTIVE;
  logic          IRQ_ACTIVE;
  logic          OLD_NMI_N;
  logic          OLD_NMI2_N;
  logic [23:0]   ADDR_BUS;

  logic [15:0]   AluR;
  logic [15:0]   AluIntR;
  logic          CO;
  logic          VO;
  logic          SO;
  logic          ZO;

  logic [16:0]   AA;
  logic [7:0]    AB;
  logic          AALCarry;
  logic [15:0]   DX;

  logic          DBG_DAT_WRr;
  logic [23:0]   DBG_BRK_ADDR;
  logic [7:0]    DBG_CTRL;
  logic          DBG_RUN_LAST;
  logic [15:0]   DBG_NEXT_PC;
  logic [23:0]   JSR_RET_ADDR;
  logic          JSR_FOUND;

  assign EN = RDY_IN & CE & (~WAIExec) & (~STPExec);

  assign IsBranchCycle1 = (IR[4:0] == 5'b10000 & STATE == 4'b0001) ? 1'b1 :
                          1'b0;


always @(posedge CLK ) begin
//	if (CE)
//	$display("RDY_OUT: %x MF: %x ADDR: %x A: %x X %x Y %x D %x SP %x T %x PC %x PBR %x DBR %x D_OUT %x D_IN %x WE %x MCODE.outbus %x irq p flag: %x IR: %x LOAD_PC: %x GOTINTERRUPT %x",RDY_OUT,MF,A_OUT,A,X,Y,D,SP,T,PC,PBR,DBR,D_OUT,D_IN,WE,MC.OUT_BUS,~P[2],IR,MC.LOAD_PC,GotInterrupt);
//if (~RST_N) $display("RESET");
	// DEBUG: Print memory write operations
	// Debug output for memory writes - commented out after debugging complete
	// if (CE && WE == 1'b0 && RST_N == 1'b1) begin
	// 	$display("WRITE: IR=%02x ADDR=%06x D_OUT=%02x PBR=%02x DBR=%02x OUT_BUS=%03b BUS_CTRL=%06b SB=%04x SP=%04x EF=%b",
	// 		IR, A_OUT, D_OUT, PBR, DBR, MC.OUT_BUS, MC.BUS_CTRL, SB, SP, EF);
	// end
end


   always_comb begin
      case (IR[7:5])
         3'b000 :
            JumpTaken = (~P[7]);
         3'b001 :
            JumpTaken = P[7];
         3'b010 :
            JumpTaken = (~P[6]);
         3'b011 :
            JumpTaken = P[6];
         3'b100 :
            JumpTaken = (~P[0]);
         3'b101 :
            JumpTaken = P[0];
         3'b110 :
            JumpTaken = (~P[1]);
         3'b111 :
            JumpTaken = P[1];
         default :
            JumpTaken = 1'b0;
      endcase
   end
   assign DLNoZero = (D[7:0] == 8'h00) ? 1'b0 :
                     1'b1;

   assign NextIR = ((STATE != 4'b0000)) ? IR :
                   (GotInterrupt == 1'b1) ? 8'h00 :
                   D_IN;


   always_comb
      case (MC.STATE_CTRL)
         3'b000 :
            NextState = STATE + 1;
         3'b001 :
            if (AALCarry == 1'b0 & (XF == 1'b1 | EF == 1'b1))
               NextState = STATE + 2;
            else
               NextState = STATE + 1;
         3'b010 :
            if (IsBranchCycle1 == 1'b1 & JumpTaken == 1'b1)
               NextState = 4'b0010;
            else
               NextState = 4'b0000;
         3'b011 :
            if (JumpNoOverflow == 1'b1 | EF == 1'b0)
               NextState = 4'b0000;
            else
               NextState = STATE + 1;
         3'b100 :
            if ((MC.LOAD_AXY[1] == 1'b0 & MF == 1'b0 & EF == 1'b0) | (MC.LOAD_AXY[1] == 1'b1 & XF == 1'b0 & EF == 1'b0))
               NextState = STATE + 1;
            else
               NextState = 4'b0000;
         3'b101 :
            if (DLNoZero == 1'b1)
               NextState = STATE + 1;
            else
               NextState = STATE + 2;
         3'b110 :
            if ((MC.LOAD_AXY[1] == 1'b0 & MF == 1'b0 & EF == 1'b0) | (MC.LOAD_AXY[1] == 1'b1 & XF == 1'b0 & EF == 1'b0))
               NextState = STATE + 1;
            else
               NextState = STATE + 2;
         3'b111 :
            if (EF == 1'b0)
               NextState = STATE + 1;
            else
               NextState = STATE + 2;
         default :
            ;
      endcase

   assign LAST_CYCLE = (NextState == 4'b0000) ? 1'b1 :
                       1'b0;


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
      begin
         STATE <= {4{1'b0}};
         IR <= {8{1'b0}};
      end
      else
      begin
         if (EN == 1'b1)
         begin
            IR <= NextIR;
            STATE <= NextState;
         end
      end


   mcode MCode(.CLK(CLK), .RST_N(RST_N), .EN(EN), .IR(NextIR), .STATE(NextState), .M(MC));


   AddrGen AddrGen(.CLK(CLK), .RST_N(RST_N), .EN(EN), .LOAD_PC(MC.LOAD_PC), .PCDec(CO), .GotInterrupt(GotInterrupt), .ADDR_CTRL(MC.ADDR_CTRL), .IND_CTRL(MC.IND_CTRL), .D_IN(D_IN), .X(X), .Y(Y), .D(D), .S(SP), .T(T), .DR(DR), .DBR(DBR), .e6502(EF), .PC(PC), .AA(AA), .AB(AB), .DX(DX), .AALCarry(AALCarry), .JumpNoOfl(JumpNoOverflow));

   assign w16 = (MC.ALU_CTRL.w16 == 1'b1) ? 1'b1 :
                (IR == 8'hEB | IR == 8'hAB) ? 1'b0 :
                ((IR == 8'h44 | IR == 8'h54) & STATE == 4'b0101) ? 1'b1 :
                ((MC.LOAD_AXY[1] == 1'b0) & MF == 1'b0 & EF == 1'b0) ? 1'b1 :
                ((MC.LOAD_AXY[1] == 1'b1) & XF == 1'b0 & EF == 1'b0) ? 1'b1 :
                1'b0;

   assign SB = (MC.BUS_CTRL[5:3] == 3'b000) ? A :
               (MC.BUS_CTRL[5:3] == 3'b001) ? X :
               (MC.BUS_CTRL[5:3] == 3'b010) ? Y :
               (MC.BUS_CTRL[5:3] == 3'b011) ? D :
               (MC.BUS_CTRL[5:3] == 3'b100) ? T :
               (MC.BUS_CTRL[5:3] == 3'b101) ? SP :
               (MC.BUS_CTRL[5:3] == 3'b110) ? {8'h00, PBR} :
               (MC.BUS_CTRL[5:3] == 3'b111) ? {8'h00, DBR} :
               16'h0000;

   assign DB = (MC.BUS_CTRL[2:0] == 3'b000) ? {8'h00, D_IN} :
               (MC.BUS_CTRL[2:0] == 3'b001) ? {D_IN, DR} :
               (MC.BUS_CTRL[2:0] == 3'b010) ? SB :
               (MC.BUS_CTRL[2:0] == 3'b011) ? D :
               (MC.BUS_CTRL[2:0] == 3'b100) ? T :
               (MC.BUS_CTRL[2:0] == 3'b101) ? 16'h0001 :
               16'h0000;


   ALU ALU(.CTRL(MC.ALU_CTRL), .L(SB), .R(DB), .w16(w16), .BCD(P[3]), .CI(P[0]), .VI(P[6]), .SI(P[7]), .CO(CO), .VO(VO), .SO(SO), .ZO(ZO), .RES(AluR), .IntR(AluIntR));

   assign MF = P[5];
   assign XF = P[4];
   assign EF = P[8];


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
      begin
         A <= {16{1'b0}};
         X <= {16{1'b0}};
         Y <= {16{1'b0}};
         SP <= 16'h0100;
         oldXF <= 1'b1;
      end
      else
      begin
         if (IR == 8'hFB & P[8] == 1'b1 & MC.LOAD_P == 3'b101)
         begin
            X[15:8] <= 8'h00;
            Y[15:8] <= 8'h00;
            SP[15:8] <= 8'h01;
            oldXF <= 1'b1;
         end
         else if (EN == 1'b1)
         begin
            if (MC.LOAD_AXY == 3'b110)
            begin
               if (MC.BYTE_SEL[1] == 1'b1 & XF == 1'b0 & EF == 1'b0)
               begin
                  X[15:8] <= AluR[15:8];
                  X[7:0] <= AluR[7:0];
               end
               else if (MC.BYTE_SEL[0] == 1'b1 & (XF == 1'b1 | EF == 1'b1))
               begin
                  X[7:0] <= AluR[7:0];
                  X[15:8] <= 8'h00;
               end
            end
            if (MC.LOAD_AXY == 3'b101)
            begin
               if (IR == 8'hEB)
               begin
                  A[15:8] <= A[7:0];
                  A[7:0] <= A[15:8];
               end
               else if ((MC.BYTE_SEL[1] == 1'b1 & MF == 1'b0 & EF == 1'b0) | (MC.BYTE_SEL[1] == 1'b1 & w16 == 1'b1))
               begin
                  A[15:8] <= AluR[15:8];
                  A[7:0] <= AluR[7:0];
               end
               else if (MC.BYTE_SEL[0] == 1'b1 & (MF == 1'b1 | EF == 1'b1))
                  A[7:0] <= AluR[7:0];
            end
            if (MC.LOAD_AXY == 3'b111)
            begin
               if (MC.BYTE_SEL[1] == 1'b1 & XF == 1'b0 & EF == 1'b0)
               begin
                  Y[15:8] <= AluR[15:8];
                  Y[7:0] <= AluR[7:0];
               end
               else if (MC.BYTE_SEL[0] == 1'b1 & (XF == 1'b1 | EF == 1'b1))
               begin
                  Y[7:0] <= AluR[7:0];
                  Y[15:8] <= 8'h00;
               end
            end

            oldXF <= XF;
            if (XF == 1'b1 & oldXF == 1'b0 & EF == 1'b0)
            begin
               X[15:8] <= 8'h00;
               Y[15:8] <= 8'h00;
            end

            case (MC.LOAD_SP)
               3'b000 :
                  ;
               3'b001 :
                  if (EF == 1'b0)
                     SP <= (SP + 1);
                  else begin
                     SP[15:8] <= 8'h01;
                     SP[7:0] <= ((SP[7:0]) + 1);
                  end
               3'b010 :
                  if (MC.BYTE_SEL[1] == 1'b0 & w16 == 1'b1)
                  begin
                     if (EF == 1'b0)
                        SP <= (SP + 1);
                     else begin
                        SP[15:8] <= 8'h01;
                        SP[7:0] <= ((SP[7:0]) + 1);
                     end
                  end
               3'b011 :
                  if (EF == 1'b0)
                     SP <= (SP - 1);
                  else begin
                     SP[15:8] <= 8'h01;
                     SP[7:0] <= ((SP[7:0]) - 1);
                  end
               3'b100 :
                  if (EF == 1'b0)
                     SP <= A;
                  else begin
                     SP[15:8] <= 8'h01;
                     SP <= {8'h01, A[7:0]};
                  end
               3'b101 :
                  if (EF == 1'b0)
                     SP <= X;
                  else begin
                     SP[15:8] <= 8'h01;
                     SP <= {8'h01, X[7:0]};
                  end
               3'b110 :
                  if (EF == 1'b0)
                     SP <= (SP + 1);
                  else begin
                     SP[15:8] <= 8'h01;
                     SP[7:0] <= ((SP[7:0]) + 1);
                  end
               3'b111 :
                  if (EF == 1'b0)
                     SP <= (SP - 1);
                  else begin
                     SP[15:8] <= 8'h01;
                     SP[7:0] <= ((SP[7:0]) - 1);
                  end
               default :
                  ;
            endcase
         end
      end


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
         P <= 9'b100110100;
      else
      begin
         if (EN == 1'b1)
            case (MC.LOAD_P)
               3'b000 :
                  P <= P;
               3'b001 :
                  if ((MC.LOAD_AXY[1] == 1'b0 & MC.BYTE_SEL[0] == 1'b1 & (MF == 1'b1 | EF == 1'b1)) | (MC.LOAD_AXY[1] == 1'b1 & MC.BYTE_SEL[0] == 1'b1 & (XF == 1'b1 | EF == 1'b1)) | (MC.LOAD_AXY[1] == 1'b0 & MC.BYTE_SEL[1] == 1'b1 & (MF == 1'b0 & EF == 1'b0)) | (MC.LOAD_AXY[1] == 1'b1 & MC.BYTE_SEL[1] == 1'b1 & (XF == 1'b0 & EF == 1'b0)) | (MC.LOAD_AXY[1] == 1'b0 & MC.BYTE_SEL[1] == 1'b1 & w16 == 1'b1) | IR == 8'hEB | IR == 8'hAB | IR == 8'h5B | IR == 8'hBA)
                  begin
                     P[1:0] <= {ZO, CO};
                     P[7:6] <= {SO, VO};
                  end
               3'b010 :
                  begin
                     P[2] <= 1'b1;
                     P[3] <= 1'b0;
                  end
               3'b011 :
                  begin
                     P[7:6] <= D_IN[7:6];
                     P[5] <= D_IN[5] | EF;
                     P[4] <= D_IN[4] | EF;
                     P[3:0] <= D_IN[3:0];
                  end
               3'b100 :
                  case (IR[7:6])
                     2'b00 :
                        P[0] <= IR[5];
                     2'b01 :
                        P[2] <= IR[5];
                     2'b10 :
                        P[6] <= 1'b0;
                     2'b11 :
                        P[3] <= IR[5];
                     default :
                        ;
                  endcase
               3'b101 :
                  begin
                     P[8] <= P[0];
                     P[0] <= P[8];
                     if (P[0] == 1'b1)
                     begin
                        P[4] <= 1'b1;
                        P[5] <= 1'b1;
                     end
                  end
               3'b110 :
                  case (IR[5])
                     1'b1 :
                        P[7:0] <= P[7:0] | ({DR[7:6], (DR[5] & (~EF)), (DR[4] & (~EF)), DR[3:0]});
                     1'b0 :
                        P[7:0] <= P[7:0] & ((~({DR[7:6], (DR[5] & (~EF)), (DR[4] & (~EF)), DR[3:0]})));
                     default :
                        ;
                  endcase
               3'b111 :
                  P[1] <= ZO;
               default :
                  ;
            endcase
      end


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
      begin
         T <= {16{1'b0}};
         DR <= {8{1'b0}};
         D <= {16{1'b0}};
         PBR <= {8{1'b0}};
         DBR <= {8{1'b0}};
      end
      else
      begin
         if (EN == 1'b1)
         begin
            DR <= D_IN;

            case (MC.LOAD_T)
               2'b01 :
                  if (MC.BYTE_SEL[1] == 1'b1)
                     T[15:8] <= D_IN;
                  else
                     T[7:0] <= D_IN;
               2'b10 :
                  T <= AluR;
               default :
                  ;
            endcase

            case (MC.LOAD_DKB)
               2'b01 :
                  D <= AluIntR;
               2'b10 :
                  if (IR == 8'h00 | IR == 8'h02)
                     PBR <= {8{1'b0}};
                  else if (IR == 8'h40 & EF == 1'b1)
                     PBR <= PBR;  // RTI in emulation mode: don't change PBR
                  else
                     PBR <= D_IN;
               2'b11 :
                  if (IR == 8'h44 | IR == 8'h54)
                     DBR <= D_IN;
                  else
                     DBR <= AluIntR[7:0];
               default :
                  ;
            endcase
         end
      end

   assign D_OUT = (MC.OUT_BUS == 3'b001) ? {P[7], P[6], (P[5] | EF), (P[4] | ((~(GotInterrupt)) & EF)), P[3:0]} :
                  (MC.OUT_BUS == 3'b010 & MC.BYTE_SEL[1] == 1'b1) ? PC[15:8] :
                  (MC.OUT_BUS == 3'b010 & MC.BYTE_SEL[1] == 1'b0) ? PC[7:0] :
                  (MC.OUT_BUS == 3'b011 & MC.BYTE_SEL[1] == 1'b1) ? AA[15:8] :
                  (MC.OUT_BUS == 3'b011 & MC.BYTE_SEL[1] == 1'b0) ? AA[7:0] :
                  (MC.OUT_BUS == 3'b100) ? PBR :
                  (MC.OUT_BUS == 3'b101 & MC.BYTE_SEL[1] == 1'b1) ? SB[15:8] :
                  (MC.OUT_BUS == 3'b101 & MC.BYTE_SEL[1] == 1'b0) ? SB[7:0] :
                  (MC.OUT_BUS == 3'b110) ? DR :
                  8'h00;


   always @*
   begin
      WE = 1'b1;
      if (MC.OUT_BUS != 3'b000 & IsResetInterrupt == 1'b0)
         WE = 1'b0;
   end


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
      begin
         OLD_NMI_N <= 1'b1;
         NMI_SYNC <= 1'b0;
      end
      else
      begin
         if (RDY_IN == 1'b1 && CE == 1'b1 & IsResetInterrupt == 1'b0)
         begin
            OLD_NMI_N <= NMI_N;
            if (NMI_N == 1'b0 & OLD_NMI_N == 1'b1 & NMI_SYNC == 1'b0)
               NMI_SYNC <= 1'b1;
            else if (LAST_CYCLE == 1'b1 && NMI_SYNC == 1'b1 && EN == 1'b1)
               NMI_SYNC <= 1'b0;
         end
      end


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
      begin
         IsResetInterrupt <= 1'b1;
         IsNMIInterrupt <= 1'b0;
         IsIRQInterrupt <= 1'b0;
         GotInterrupt <= 1'b1;
      end
      else
      begin
         if (RDY_IN == 1'b1 & CE == 1'b1)
         begin
            if (LAST_CYCLE == 1'b1 & EN == 1'b1)
            begin
               if (GotInterrupt == 1'b0)
                  GotInterrupt <= IRQ_ACTIVE | NMI_ACTIVE;
               else
                  GotInterrupt <= 1'b0;

               IsResetInterrupt <= 1'b0;
               IsNMIInterrupt <= NMI_ACTIVE;
               IsIRQInterrupt <= IRQ_ACTIVE;
            end
         end
      end

   assign IsBRKInterrupt = (IR == 8'h00) ? 1'b1 :
                           1'b0;
   assign IsCOPInterrupt = (IR == 8'h02) ? 1'b1 :
                           1'b0;
   assign IsABORTInterrupt = 1'b0;


   always @(posedge CLK or negedge RST_N)
      if (RST_N == 1'b0)
      begin
         WAIExec <= 1'b0;
         STPExec <= 1'b0;
      end
      else
      begin
         if (EN == 1'b1 & GotInterrupt == 1'b0)
         begin
            if (STATE == 4'b0001)
            begin
               if (IR == 8'hCB)
                  WAIExec <= 1'b1;
               else if (IR == 8'hDB)
                  STPExec <= 1'b1;
            end
         end

         if (RDY_IN == 1'b1 & CE == 1'b1)
         begin
            if ((NMI_SYNC == 1'b1 | IRQ_N == 1'b1 | ABORT_N == 1'b0) & WAIExec == 1'b1)
               WAIExec <= 1'b0;
         end
      end


   always @*
   begin: xhdl0
      logic [15:0]     ADDR_INC;
      ADDR_INC = { 14'b0, MC.ADDR_INC[1:0] };
      case (MC.ADDR_BUS)
         4'b0000 :
            ADDR_BUS = {PBR, PC};
         4'b0001 :
            ADDR_BUS = (({DBR, 16'h0000}) + ({8'h00, (AA[15:0])}) + ({8'h00, ADDR_INC}));
         4'b0101 :
            ADDR_BUS = (({AB, 16'h0000}) + ({7'b0000000, AA}) + ({8'h00, ADDR_INC}));
         4'b0010 :
            ADDR_BUS = {PBR, ((AA[15:0]) + ADDR_INC)};
         4'b0110 :
            ADDR_BUS = {8'h00, ((AA[15:0]) + ADDR_INC)};
         4'b0011, 4'b0111 :
            if (EF == 1'b0 || MC.ADDR_BUS[2] == 1'b0 || D[7:0] != 8'h00)
               ADDR_BUS = {8'h00, (DX + ADDR_INC)};
            else
               // Emulation mode with DL=0: force page wrapping
               ADDR_BUS = {8'h00, DX[15:8], DX[7:0] + ADDR_INC[7:0]};
         4'b1000, 4'b1100 :
            if (EF == 1'b0)
               ADDR_BUS = {8'h00, SP};  // Native mode - use full SP
            else
               ADDR_BUS = {16'h0001, SP[7:0]};  // Emulation mode - always force page 1
         4'b1111 :
            begin
               ADDR_BUS[23:4] = {8'h00, 11'b11111111111, EF};
               if (IsResetInterrupt == 1'b1)
                  ADDR_BUS[3:0] = {3'b110, MC.ADDR_INC[0]};
               else if (IsABORTInterrupt == 1'b1)
                  ADDR_BUS[3:0] = {3'b100, MC.ADDR_INC[0]};
               else if (IsNMIInterrupt == 1'b1)
                  ADDR_BUS[3:0] = {3'b101, MC.ADDR_INC[0]};
               else if (IsIRQInterrupt == 1'b1)
                  ADDR_BUS[3:0] = {3'b111, MC.ADDR_INC[0]};
               else if (IsCOPInterrupt == 1'b1)
                  ADDR_BUS[3:0] = {3'b010, MC.ADDR_INC[0]};
               else
                  ADDR_BUS[3:0] = {EF, 2'b11, MC.ADDR_INC[0]};
            end
         default :
            ADDR_BUS = 24'h000000;
      endcase
   end

   assign A_OUT = ADDR_BUS;


   always @*
   begin: xhdl1
      logic           rmw;
      logic           twoCls;
      logic           softInt;
      if (IR == 8'h06 | IR == 8'h0E | IR == 8'h16 | IR == 8'h1E | IR == 8'hC6 | IR == 8'hCE | IR == 8'hD6 | IR == 8'hDE | IR == 8'hE6 | IR == 8'hEE | IR == 8'hF6 | IR == 8'hFE | IR == 8'h46 | IR == 8'h4E | IR == 8'h56 | IR == 8'h5E | IR == 8'h26 | IR == 8'h2E | IR == 8'h36 | IR == 8'h3E | IR == 8'h66 | IR == 8'h6E | IR == 8'h76 | IR == 8'h7E | IR == 8'h14 | IR == 8'h1C | IR == 8'h04 | IR == 8'h0C)
         rmw = 1'b1;
      else
         rmw = 1'b0;

      if (MC.ADDR_BUS == 4'b1111)
         VPB = 1'b0;
      else
         VPB = 1'b1;

      if ((MC.ADDR_BUS == 4'b0001 | MC.ADDR_BUS == 4'b0011 | MC.ADDR_BUS == 4'b0111) & rmw == 1'b1)
         MLB = 1'b0;
      else
         MLB = 1'b1;

      if (LAST_CYCLE == 1'b1 & STATE == 1 & MC.VA == 2'b00)
         twoCls = 1'b1;
      else
         twoCls = 1'b0;

      if ((IsBRKInterrupt == 1'b1 | IsCOPInterrupt == 1'b1) & STATE == 1 & GotInterrupt == 1'b0)
         softInt = 1'b1;
      else
         softInt = 1'b0;

      VDA = MC.VA[1];
      VPA = MC.VA[0] | (twoCls & (IRQ_ACTIVE | NMI_ACTIVE)) | softInt;
   end

   assign RDY_OUT = EN;

endmodule
