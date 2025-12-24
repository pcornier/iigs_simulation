
module prtc(
  input CLK_14M,
  input cen,
  input reset,
  input addr,
  input [32:0] timestamp,
  input [7:0] din,
  output reg [7:0] dout,
  output reg onesecond_irq,
  output reg qtrsecond_irq,
  input rw,
  input strobe // must be high for one clock enable(cen) only!
);

reg old_strobe;
reg [7:0] pram [255:0];
/*
rom #(8,8,"rtl/roms/nvram.hex") hddrom (
           .clock(clk),
           .ce(1'b1),
           .address(A[7:0]),
           .q(rom_dout)
   );
*/

/*
initial begin
pram[8'h0]=8'h0;
pram[8'h1]=8'h0;
pram[8'h2]=8'h0;
pram[8'h3]=8'h1;
pram[8'h4]=8'h0;
pram[8'h5]=8'h0;
pram[8'h6]=8'hd;
pram[8'h7]=8'h6;
pram[8'h8]=8'h2;
pram[8'h9]=8'h1;
pram[8'ha]=8'h1;
pram[8'hb]=8'h0;
pram[8'hc]=8'h1;
pram[8'hd]=8'h0;
pram[8'he]=8'h0;
pram[8'hf]=8'h0;
pram[8'h10]=8'h0;
pram[8'h11]=8'h0;
pram[8'h12]=8'h7;
pram[8'h13]=8'h6;
pram[8'h14]=8'h2;
pram[8'h15]=8'h1;
pram[8'h16]=8'h1;
pram[8'h17]=8'h0;
pram[8'h18]=8'h0;
pram[8'h19]=8'h0;
pram[8'h1a]=8'hf;
pram[8'h1b]=8'h5;
pram[8'h1c]=8'h1;
pram[8'h1d]=8'h0;
pram[8'h1e]=8'h5;
pram[8'h1f]=8'h6;
pram[8'h20]=8'h1;
pram[8'h21]=8'h0;
pram[8'h22]=8'h0;
pram[8'h23]=8'h0;
pram[8'h24]=8'h0;
pram[8'h25]=8'h1;
pram[8'h26]=8'h1;
pram[8'h27]=8'h1;
pram[8'h28]=8'h7;
pram[8'h29]=8'h0;
pram[8'h2a]=8'h0;
pram[8'h2b]=8'h0;
pram[8'h2c]=8'h3;
pram[8'h2d]=8'h2;
pram[8'h2e]=8'h2;
pram[8'h2f]=8'h2;
pram[8'h30]=8'h0;
pram[8'h31]=8'h0;
pram[8'h32]=8'h0;
pram[8'h33]=8'h0;
pram[8'h34]=8'h0;
pram[8'h35]=8'h0;
pram[8'h36]=8'h0;
pram[8'h37]=8'h0;
pram[8'h38]=8'h0;
pram[8'h39]=8'h0;
pram[8'h3a]=8'h1;
pram[8'h3b]=8'h2;
pram[8'h3c]=8'h3;
pram[8'h3d]=8'h4;
pram[8'h3e]=8'h5;
pram[8'h3f]=8'h6;
pram[8'h40]=8'h7;
pram[8'h41]=8'h0;
pram[8'h42]=8'h0;
pram[8'h43]=8'h1;
pram[8'h44]=8'h2;
pram[8'h45]=8'h3;
pram[8'h46]=8'h4;
pram[8'h47]=8'h5;
pram[8'h48]=8'h6;
pram[8'h49]=8'h7;
pram[8'h4a]=8'h8;
pram[8'h4b]=8'h9;
pram[8'h4c]=8'ha;
pram[8'h4d]=8'hb;
pram[8'h4e]=8'hc;
pram[8'h4f]=8'hd;
pram[8'h50]=8'he;
pram[8'h51]=8'hf;
pram[8'h52]=8'hff;
pram[8'h53]=8'hff;
pram[8'h54]=8'hff;
pram[8'h55]=8'hff;
pram[8'h56]=8'hff;
pram[8'h57]=8'hff;
pram[8'h58]=8'hff;
pram[8'h59]=8'h0;
pram[8'h5a]=8'hff;
pram[8'h5b]=8'hff;
pram[8'h5c]=8'hff;
pram[8'h5d]=8'hff;
pram[8'h5e]=8'hff;
pram[8'h5f]=8'h81;
pram[8'h60]=8'hff;
pram[8'h61]=8'hff;
pram[8'h62]=8'hff;
pram[8'h63]=8'hff;
pram[8'h64]=8'hff;
pram[8'h65]=8'hff;
pram[8'h66]=8'hff;
pram[8'h67]=8'hff;
pram[8'h68]=8'hff;
pram[8'h69]=8'hff;
pram[8'h6a]=8'hff;
pram[8'h6b]=8'hff;
pram[8'h6c]=8'hff;
pram[8'h6d]=8'hff;
pram[8'h6e]=8'hff;
pram[8'h6f]=8'hff;
pram[8'h70]=8'hff;
pram[8'h71]=8'hff;
pram[8'h72]=8'hff;
pram[8'h73]=8'hff;
pram[8'h74]=8'hff;
pram[8'h75]=8'hff;
pram[8'h76]=8'hff;
pram[8'h77]=8'hff;
pram[8'h78]=8'hff;
pram[8'h79]=8'hff;
pram[8'h7a]=8'hff;
pram[8'h7b]=8'hff;
pram[8'h7c]=8'hff;
pram[8'h7d]=8'hff;
pram[8'h7e]=8'hff;
pram[8'h7f]=8'hff;
pram[8'h80]=8'hff;
pram[8'h81]=8'hff;
pram[8'h82]=8'hff;
pram[8'h83]=8'hff;
pram[8'h84]=8'hff;
pram[8'h85]=8'hff;
pram[8'h86]=8'hff;
pram[8'h87]=8'hff;
pram[8'h88]=8'hff;
pram[8'h89]=8'hff;
pram[8'h8a]=8'hff;
pram[8'h8b]=8'hff;
pram[8'h8c]=8'hff;
pram[8'h8d]=8'hff;
pram[8'h8e]=8'hff;
pram[8'h8f]=8'hff;
pram[8'h90]=8'hff;
pram[8'h91]=8'hff;
pram[8'h92]=8'hff;
pram[8'h93]=8'hff;
pram[8'h94]=8'hff;
pram[8'h95]=8'hff;
pram[8'h96]=8'hff;
pram[8'h97]=8'hff;
pram[8'h98]=8'hff;
pram[8'h99]=8'hff;
pram[8'h9a]=8'hff;
pram[8'h9b]=8'hff;
pram[8'h9c]=8'hff;
pram[8'h9d]=8'hff;
pram[8'h9e]=8'hff;
pram[8'h9f]=8'hff;
pram[8'ha0]=8'hff;
pram[8'ha1]=8'hff;
pram[8'ha2]=8'hff;
pram[8'ha3]=8'hff;
pram[8'ha4]=8'hff;
pram[8'ha5]=8'hff;
pram[8'ha6]=8'hff;
pram[8'ha7]=8'hff;
pram[8'ha8]=8'hff;
pram[8'ha9]=8'hff;
pram[8'haa]=8'hff;
pram[8'hab]=8'hff;
pram[8'hac]=8'hff;
pram[8'had]=8'hff;
pram[8'hae]=8'hff;
pram[8'haf]=8'hff;
pram[8'hb0]=8'hff;
pram[8'hb1]=8'hff;
pram[8'hb2]=8'hff;
pram[8'hb3]=8'hff;
pram[8'hb4]=8'hff;
pram[8'hb5]=8'hff;
pram[8'hb6]=8'hff;
pram[8'hb7]=8'hff;
pram[8'hb8]=8'hff;
pram[8'hb9]=8'hff;
pram[8'hba]=8'hff;
pram[8'hbb]=8'hff;
pram[8'hbc]=8'hff;
pram[8'hbd]=8'hff;
pram[8'hbe]=8'hff;
pram[8'hbf]=8'hff;
pram[8'hc0]=8'hff;
pram[8'hc1]=8'hff;
pram[8'hc2]=8'hff;
pram[8'hc3]=8'hff;
pram[8'hc4]=8'hff;
pram[8'hc5]=8'hff;
pram[8'hc6]=8'hff;
pram[8'hc7]=8'hff;
pram[8'hc8]=8'hff;
pram[8'hc9]=8'hff;
pram[8'hca]=8'hff;
pram[8'hcb]=8'hff;
pram[8'hcc]=8'hff;
pram[8'hcd]=8'hff;
pram[8'hce]=8'hff;
pram[8'hcf]=8'hff;
pram[8'hd0]=8'hff;
pram[8'hd1]=8'hff;
pram[8'hd2]=8'hff;
pram[8'hd3]=8'hff;
pram[8'hd4]=8'hff;
pram[8'hd5]=8'hff;
pram[8'hd6]=8'hff;
pram[8'hd7]=8'hff;
pram[8'hd8]=8'hff;
pram[8'hd9]=8'hff;
pram[8'hda]=8'hff;
pram[8'hdb]=8'hff;
pram[8'hdc]=8'hff;
pram[8'hdd]=8'hff;
pram[8'hde]=8'hff;
pram[8'hdf]=8'hff;
pram[8'he0]=8'hff;
pram[8'he1]=8'hff;
pram[8'he2]=8'hff;
pram[8'he3]=8'hff;
pram[8'he4]=8'hff;
pram[8'he5]=8'hff;
pram[8'he6]=8'hff;
pram[8'he7]=8'hff;
pram[8'he8]=8'hff;
pram[8'he9]=8'hff;
pram[8'hea]=8'hff;
pram[8'heb]=8'hff;
pram[8'hec]=8'hff;
pram[8'hed]=8'hff;
pram[8'hee]=8'hff;
pram[8'hef]=8'hff;
pram[8'hf0]=8'hff;
pram[8'hf1]=8'hff;
pram[8'hf2]=8'hff;
pram[8'hf3]=8'hff;
pram[8'hf4]=8'hff;
pram[8'hf5]=8'hff;
pram[8'hf6]=8'hff;
pram[8'hf7]=8'hff;
pram[8'hf8]=8'hff;
pram[8'hf9]=8'hff;
pram[8'hfa]=8'hff;
pram[8'hfb]=8'hff;
pram[8'hfc]=8'h71;
pram[8'hfd]=8'h53;
pram[8'hfe]=8'hdb;
pram[8'hff]=8'hf9;
`ifdef SIMULATION
// Seed to deterministic values; CTL starts at 0x00 to match early read
c033 = 8'h06;   // DATA
c034 = 8'h00;   // CTL initial read returns 0x00
`else
c033 = 8'h00;
c034 = 8'h00;
`endif
end
*/

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



reg [24:0] clock_counter;
reg [24:0] clock_counter2;



reg [2:0] state;
reg [1:0] checksum_state;
reg [1:0] checksum_writes;
reg [31:0] checksum;
reg [7:0] counter;
reg [7:0] clk_reg1;

reg [31:0] timestamp_prev;

always @(posedge CLK_14M) begin

	onesecond_irq<=0;
    qtrsecond_irq<=0;

// Initialize clock deterministically under simulation to avoid nondeterministic diffs
// Otherwise, hook up host timestamp (Mac epoch) on first use
//`ifdef SIMULATION
//if (clock_data==0)
//	clock_data <= 32'h0600_0000; // match Clemens early read of C033 (high byte = $06)
//`else
// hook up unix timestamp
if (clock_data==0)
	clock_data <= timestamp[31:0] + 2082844800; // difference between unix epoch and mac epoch
//`endif

if (timestamp_prev!=timestamp)
	clock_data <= timestamp[31:0] + 2082844800; // difference between unix epoch and mac epoch

timestamp_prev<= timestamp;


// Use real hardware timing for both FPGA and simulation
// Modern computers are fast enough to handle this
clock_counter<=clock_counter+1;
clock_counter2<=clock_counter2+1;
if (clock_counter=='d14318181)
begin
	clock_counter<=0;
	onesecond_irq<=1;
	clock_data<=clock_data+1;
`ifdef SIMULATION
	$display("PRTC: One-second interrupt fired");
`endif
end
if (clock_counter2=='d3818186)
begin
	clock_counter2<=0;
	qtrsecond_irq<=1;
`ifdef SIMULATION
	$display("PRTC: Quarter-second interrupt fired");
`endif
end


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
