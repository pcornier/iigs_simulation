`timescale 1ns/1ns

module es5503
   (input	      clk,
    input	      osc_en,
    input	      reset,
    input	      wr,
    input [7:0]	      reg_addr,
    input [7:0]	      reg_data_in,
    input [7:0]	      sample_data_in,
    output reg [7:0]  data_out,
    output reg [16:0] addr_out,
    output reg [15:0] sound_out,
    output [3:0]      ca,
    output	      irq
    );

   // Global configuration
   reg [4:0]	     oscs_enabled;

   // Global state
   reg [4:0]	     current_osc;
   reg		     refreshing;
   reg		     current_refresh;

   // Per-oscillator configuration
   reg [7:0]	     r_freq_low    [31:0];
   reg [7:0]	     r_freq_high   [31:0];
   reg [7:0]	     r_volume      [31:0];
   reg [7:0]	     r_sample_data [31:0];
   reg [7:0]	     r_table_ptr   [31:0];
   reg [7:0]	     r_control     [31:0];
   reg [7:0]	     r_table_size  [31:0];

   // Oscillator state
   reg [23:0]	     accumulator [31:0];
   reg [31:0]	     irq_pending;
   reg [4:0]	     irq_stack [31:0];
   reg [4:0]	     irq_sp;

   // Accumulator adder / wrap detection
   wire [24:0]	     accumulator_sum;
   wire [24:0]	     accumulator_flip;
   wire		     accumulator_wrapped;

   assign accumulator_sum = accumulator[current_osc] +
			    {9'b0,
			     r_freq_high[current_osc],
			     r_freq_low[current_osc]};

   assign accumulator_flip ={accumulator_sum[24],
			     accumulator_sum[23:0] ^ accumulator[current_osc]};

   assign accumulator_wrapped = accumulator_flip[17 + {2'b00, r_table_size[current_osc][2:0]}];

   assign irq = |irq_pending;

   integer	     i;

   task log_keyon (input [4:0] osc);
      $display("Key on: osc %d vol %h freq %h ptr %h size %h control %h",
	       osc, r_volume[osc], {r_freq_high[osc], r_freq_low[osc]},
	       r_table_ptr[osc], r_table_size[osc], r_control[osc]);
   endtask // log_keyon

   function [15:0] mux_addr (input [23:0] acc,
			     input [7:0]  tbl_ptr,
			     input [2:0]  tbl_index,
			     input [2:0]  res_index);
      reg [7:0]				  ptr_mask;
      reg [15:0]			  acc_mask;
      reg [23:0]			  acc_shifted;
      reg [15:0]			  acc_bits;
      reg [15:0]			  ptr_bits;
      begin
	 assign ptr_mask = 8'hff << tbl_index;
	 assign acc_mask = (16'hffff >> (8 - tbl_index));
	 assign acc_shifted = acc >> (9 + res_index - tbl_index); 
	 assign acc_bits = acc_shifted[15:0] & acc_mask;
	 assign ptr_bits = ({8'h0, tbl_ptr} & {8'h0, ptr_mask[7:0]}) << 8;

	 mux_addr = acc_bits[15:0] | ptr_bits;
      end
   endfunction // mux_addr

   always @(posedge clk) begin
      addr_out <= {r_table_size[current_osc][6],
		   mux_addr(accumulator[current_osc],
			    r_table_ptr[current_osc],
			    r_table_size[current_osc][5:3],
			    r_table_size[current_osc][2:0])};

      if (wr) begin
	 $display("%m: CPU write %h=%h", reg_addr, reg_data_in);
	 case (reg_addr[7:5])
	   0: begin
	      //if (current_osc == 0)
		//$display("freq_low[0] <= %h", reg_data_in);
	      r_freq_low[reg_addr[4:0]] <= reg_data_in;
	   end
	   1: begin r_freq_high[reg_addr[4:0]] <= reg_data_in;
	      //if (current_osc == 0)
		//$display("freq_high[0] <= %h", reg_data_in);
	   end
	   2: r_volume[reg_addr[4:0]] <= reg_data_in;
	   // r_sample_data; read-only
	   4: r_table_ptr[reg_addr[4:0]] <= reg_data_in;
	   5: begin
	      r_control[reg_addr[4:0]] <= reg_data_in;
	      if (r_control[reg_addr[4:0]][0] && !reg_data_in[0]) begin
		 accumulator[reg_addr[4:0]] <= 0;
		 //log_keyon(reg_addr[4:0]);
	      end
	   end
	   6: r_table_size[reg_addr[4:0]] <= reg_data_in;
	   7: case (reg_addr[1:0])
		// OIR; read-only
		1: oscs_enabled <= reg_data_in[5:1];
		// ADC; read-only
	      endcase // case (reg_addr[1:0])
	 endcase // case (reg_addr[7:5])
      end // if (wr)
      else begin // read
	 case (reg_addr[7:5])
	   0: data_out <= r_freq_low[reg_addr[4:0]];
	   1: data_out <= r_freq_high[reg_addr[4:0]];
	   2: data_out <= r_volume[reg_addr[4:0]];
	   3: data_out <= r_sample_data[reg_addr[4:0]];
	   4: data_out <= r_table_ptr[reg_addr[4:0]];
	   5: data_out <= r_control[reg_addr[4:0]];
	   6: data_out <= r_table_size[reg_addr[4:0]];
	   7: case (reg_addr[1:0])
		0: begin // OIR
		   if (irq_sp == 0) begin
		      data_out <= {2'b11, irq_stack[0], 1'b1};
		   end else begin
		      data_out <= {2'b01, irq_stack[irq_sp - 1], 1'b1};
		      irq_pending[irq_stack[irq_sp - 1]] <= 1'b0;
		      irq_sp <= irq_sp - 1;
		   end
		end
		1: data_out <= {2'b0, oscs_enabled, 1'b0};
		// ADC; not implemented
	      endcase // case (reg_addr[1:0])
	 endcase // case (reg_addr[7:5])
      end // else: !if(wr)

      if (osc_en) begin
	 if (current_osc == oscs_enabled && !refreshing) begin
	    refreshing <= 1;
	    current_refresh <= 0;
	 end
	 else if (refreshing) begin
	    if (current_refresh) begin
	       refreshing <= 0;
	       current_osc <= 0;
	    end
	    else
	      current_refresh <= 1;
	 end
	 else
	   current_osc <= current_osc + 1;
	 if (!r_control[current_osc][0]) begin
	    //$display("Osc %d running", current_osc);
	    // Accumulator/halt update
	    accumulator[current_osc] <= accumulator_sum[23:0];
	    if (accumulator_wrapped || sample_data_in == 8'h00) begin
	       r_control[current_osc][0] <= (r_control[current_osc][1] || sample_data_in == 8'h00);
	       if (r_control[current_osc][1])
		 accumulator[current_osc] <= 0;
	       // IRQ handling
	       if (r_control[current_osc][3] && !irq_pending[current_osc]) begin
		  irq_pending[current_osc] <= 1;
		  irq_stack[irq_sp] <= current_osc;
		  irq_sp <= irq_sp + 1;
	       end
	    end

	    // Wavetable sample update
	    r_sample_data[current_osc] <= sample_data_in;

	    // Output sample update
	    sound_out <= $signed(sample_data_in ^ 8'h80) *
			 $signed({8'b0, r_volume[current_osc]});
	    ca <= r_control[current_osc][7:4];
	 end // if (!r_control[current_osc][0])
	 else begin
	    sound_out <= 16'h0000;
	 end // else: !if(!r_control[current_osc][0])
      end // if (osc_en)

      if (reset) begin
	 oscs_enabled <= 0;
	 current_osc <= 0;
	 refreshing <= 0;
	 current_refresh <= 0;
	 for (i=0; i < 32; i=i+1) accumulator[i] <= 0;
	 irq_pending <= 0;
	 irq_sp <= 0;
	 //irq_stack[0] <= 8'hff
      end
   end // always @ (posedge clk)
endmodule // es5503
