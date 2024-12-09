module soundglu
  (input	     clk,  // TODO?: This is currently 28.6 MHz
   input	     reset,
   input	     select,
   input	     wr,
   input [1:0]	     host_addr,
   input [7:0]	     host_data_in,
   input [7:0]	     sound_data_in,
   output reg	     ram_access,
   output reg [7:0]  host_data_out,
   output reg [15:0] sound_addr,
   output reg [7:0]  sound_data_out,
   output reg	     ram_wr,
   output reg        doc_wr,
   output reg	     doc_enable
   );

   localparam	     ST_IDLE = 0;
   localparam	     ST_PENDING = 1;
   localparam	     ST_FINISHING = 2;

   reg		    auto_increment;
   reg [3:0]	    volume;
   reg		    select_d;
   reg [4:0]	    clk_phase;
   reg [1:0]	    sound_cycle_state;
   reg		    sound_write_pending;
   reg [7:0]	    read_data_reg;

   always @(posedge clk) begin
      clk_phase <= clk_phase + 1;
      doc_enable <= clk_phase == 0;
      doc_wr <= 0;
      ram_wr <= 0;
      select_d <= select;

      // doc_enable high means the DOC just executed its cycle, so it's
      // time to execute the pending host access
      if (sound_cycle_state == ST_PENDING && doc_enable) begin
	 sound_cycle_state <= ST_FINISHING;
	 doc_wr <= !ram_access && sound_write_pending;
	 ram_wr <= ram_access && sound_write_pending;
      end
      else if (sound_cycle_state == ST_FINISHING) begin
	 sound_write_pending <= 0;
	 sound_cycle_state <= ST_IDLE;

	 if (!sound_write_pending)
	   read_data_reg <= sound_data_in;
	 
	 if (auto_increment)
	   sound_addr <= sound_addr + 1;
      end

      // CPU interface
      if (!select_d && select) begin
	 if (wr) begin
	    case (host_addr)
	      0: begin // Sound Control
		 $display("%m: %h => SNDCTL", host_data_in);
		 ram_access <= host_data_in[6];
		 auto_increment <= host_data_in[5];
		 volume <= host_data_in[3:0];
	      end
	      1: begin // Sound Data
		 if (!ram_access)
		   $display("%m: %h => SNDDATA", host_data_in);
		 sound_cycle_state <= ST_PENDING;
		 sound_write_pending <= 1;
		 sound_data_out <= host_data_in;
	      end
	      2: begin
		 sound_addr[7:0] <= host_data_in;  // Address Pointer Low
		 $display("%m: %h => SNDAPL", host_data_in);
	      end
	      3: begin
		 sound_addr[15:8] <= host_data_in; // Address Pointer High
		 $display("%m: %h => SNDAPH", host_data_in);
	      end
	    endcase // case (host_addr)
	 end // if (wr)
	 else begin
	    case (host_addr)
	      0: host_data_out <= {sound_cycle_state == ST_PENDING, ram_access, auto_increment, 1'b1, volume}; // Sound Control
	      1: begin // Sound Data
		 sound_cycle_state <= ST_PENDING;
		 sound_write_pending <= 0;
		 host_data_out <= read_data_reg; 
		 read_data_reg <= sound_data_in;
	      end
	      2: host_data_out <= sound_addr[7:0];  // Address Pointer Low
	      3: host_data_out <= sound_addr[15:8]; // Address Pointer High
	    endcase
	 end // else: !if(wr)
      end // if (!select_d && select)

      if (reset) begin
	 clk_phase <= 0;
	 sound_cycle_state <= ST_IDLE;
	 sound_write_pending <= 0;
      end
   end // always @ (posedge clk)
endmodule // soundglu
