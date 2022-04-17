
module prtc(
  input clk,
  input cen,
  input reset,
  input addr,
  input [7:0] din,
  output reg [7:0] dout,
  input rw,
  input strobe // must be high for one clock enable(cen) only!
);

reg old_strobe;
reg [7:0] pram [255:0];

reg [31:0] clock_data;
reg [7:0] c033, c034;

// calculate checksum, not tested!!
// it will start when checksum_state = 1;

parameter
  IDLE = 3'd0,
  WAIT = 3'd1,
  PRAM = 3'd2,
  CLOCK = 3'd3,
  INTERNAL = 3'd4;

reg [2:0] state;
reg [1:0] checksum_state;
reg [1:0] checksum_writes;
reg [31:0] checksum;
reg [7:0] counter;
reg [7:0] clk_reg1;
always @(posedge clk) begin
  case (checksum_state)
    2'd1: begin
      checksum_state <= 2'd2;
      checksum <= 32'd0;
      counter <= 8'd250;
      checksum_writes <= 2'd0;
    end
    2'd2: begin
      checksum <= checksum[31:16] + { checksum[14:0], 1'b0 } + { pram[counter+1], pram[counter] };
      if (counter == 8'd0) begin
        checksum <= { checksum[15:0] ^ 16'haaaa, checksum[15:0] };
        checksum_state <= 2'd3;
      end
      else begin
        counter <= counter - 8'd1;
      end
    end
    2'd3: begin
      pram[252+checksum_writes] <= checksum[(checksum_writes*8)-1+:8];
      checksum_writes <= checksum_writes + 2'd1;
      if (checksum_writes == 2'd3) checksum_state <= 2'd0;
    end
  endcase


  // c033 (DATA)
  if (addr == 1'b0) begin
    if (rw)
      dout <= c033;
    else
      c033 <= din;
  end

  // c034
  if (addr == 1'b1) begin
    if (rw)
      dout <= c034;
    else
      c034 <= din[6:0];
  end

  // old_strobe <= strobe;
  if (strobe && cen) begin

    // write c034 (CTL)
    if (addr == 1'b1 && ~rw) begin

      if (din[7]) begin // start transaction

        case (state)

          IDLE: begin

            casez (c033)
              8'b?000??01: begin // clock
                state <= CLOCK;
                clk_reg1 <= { 6'd0, c033[3:2] }; // save clk register
              end
              8'b00110?01: begin // internal registers
                state <= INTERNAL;
                clk_reg1[0] <= c033[2]; // save internal register
              end
              8'b?010??01: begin // BRAM 100ab
                clk_reg1 <= { 6'b000100, c033[3:2] };
                state <= PRAM;
              end
              8'b?1????01: begin // BRAM 0abcd
                clk_reg1 <= { 4'b0, c033[3:0] };
                state <= PRAM;
              end
              8'b?0111???: begin // BRAM { abc, ????? }
                clk_reg1[7:5] <= c033[2:0];
                state <= WAIT;
              end
            endcase
          end

          WAIT: begin // BRAM { ???, defgh }
            clk_reg1[4:0] <= c033[6:2];
            state <= PRAM;
            state <= PRAM;
          end

          PRAM: begin

            // gsplus has logic here for boot slot
            // it will need checksum calculation (checksum_state <= 2'b1)

            state <= IDLE;

            if (c034[6]) // read
              c033 <= pram[clk_reg1];
            else
              pram[clk_reg1] <= c033;

          end

          CLOCK: begin

            state <= IDLE;

            if (c034[6]) // read
              c033 <= clock_data[clk_reg1*8+:8];
            else // write
              clock_data[clk_reg1*8+:8] <= c033;

          end

          INTERNAL: begin

            state <= IDLE;

            case (clk_reg1[0])
              1'b0: ; // test register
              1'b1: ; // write protect register
            endcase

          end

        endcase

      end

    end

  end

end

endmodule
