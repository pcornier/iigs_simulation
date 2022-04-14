
module adb(
  input clk,
  input cen,
  input reset,
  input [7:0] addr,
  input rw,
  input [7:0] din,
  output reg [7:0] dout,
  output irq,
  input strobe
);

parameter VERSION = 1;

parameter
  IDLE = 3'd0,
  CMD = 3'd1,
  DATA = 3'd2;

reg [1:0] state;
reg soft_reset;
reg [7:0] interrupt;
reg pending_irq;
reg [2:0] pending_data;
reg [31:0] data;
reg [7:0] cmd;
reg [2:0] cmd_len;
reg [63:0] cmd_data;
reg [7:0] adb_mode;
reg [7:0] kbd_ctl_addr = 8'd2;
reg [7:0] mouse_ctl_addr = 8'd3;
reg [7:0] repeat_rate, repeat_delay;
reg [7:0] char_set = 8'd0;
reg [7:0] layout = 8'd0;
reg [7:0] repeat_info = 8'h23;

reg data_int, mouse_int, kbd_int;

wire data_irq = data_int & pending_data;
wire mouse_irq = mouse_int & valid_mouse_data;
wire kbd_irq = kbd_int & valid_kbd;
assign irq = data_irq | mouse_irq | kbd_irq;


reg valid_mouse_data;
reg valid_kbd;
reg mouse_coord;
reg cmd_full;

reg [7:0] ram[255:0];

reg [7:0] c025;


  // todo: read c024 mouse data
  // todo: read c000 - keyboard data
  // todo: access C010 - reset keydown flag bit 7 in c000
  

always @(posedge clk) begin

  if (reset | soft_reset) begin
    soft_reset <= 1'b0;
    data_int <= 1'b1;
    // todo
  end

  case (addr)

    8'h25: begin

      if (rw) dout <= c025;

    end

    8'h26: begin

      // read c026
      if (rw) begin

        case (state)
          IDLE: begin
            dout <= data[7:0];
            if (pending_irq) dout <= 8'b0001_0000;
            if (pending_data > 3'd0) state <= DATA;
          end
          CMD: dout <= 8'd0;
          DATA: begin
            dout <= data[7:0];
            if (cen & strobe) begin
              data <= { 8'd0, data[31:8] };
              if (pending_data > 3'd0) pending_data <= pending_data - 3'd1;
              if (pending_data == 3'd1) state <= IDLE;
            end
          end
        endcase


      end

      // write c026
      else if (cen & strobe) begin

        case (state)

          IDLE: begin

            cmd <= din;

            case (din)
              8'h01: ; // abort
              8'h03: ; // flush keyboard buffer
              8'h04: begin cmd_len <= 3'd1; state <= CMD; end
              8'h05: begin cmd_len <= 3'd1; state <= CMD; end
              8'h06: begin cmd_len <= 3'd3; state <= CMD; end
              8'h07: begin cmd_len <= VERSION == 1 ? 3'd4 : 3'd8; state <= CMD; end
              8'h08: begin cmd_len <= 3'd2; state <= CMD; end
              8'h09: begin cmd_len <= 3'd2; state <= CMD; end
              8'h0a: begin
                data <= { data[23:0], adb_mode };
                pending_data <= 3'd1;
              end
              8'h0b: begin
                data <= {
                  mouse_ctl_addr,
                  kbd_ctl_addr,
                  char_set,
                  layout,
                  repeat_info
                };
                pending_data <= 3'd1;
              end
              8'h0d: begin
                data <= { data[23:0] , (VERSION == 1 ? 8'd5 : 8'd6) };
                pending_data <= 3'd1;
              end
              8'h0e: begin // read charsets
                data <= { data[15:0], 8'd0, 8'd1 };
                pending_data <= 3'd2;
              end
              8'h0f: begin // read layouts
                data <= { data[15:0], 8'd0, 8'h1 };
                pending_data <= 3'd2;
              end
              8'h10: soft_reset <= 1'b1;
              8'h11: begin cmd_len <= 3'd1; state <= CMD; end
              8'h12: if (VERSION >= 3) begin cmd_len <= 3'd2; state <= CMD; end
              8'h13: if (VERSION >= 3) begin cmd_len <= 3'd2; state <= CMD; end
              8'h73: ; // disable SRQ on mouse
              8'hb0, 8'hb1, 8'hb2, 8'hb3,
              8'hb4, 8'hb5, 8'hb6, 8'hb7,
              8'hb8, 8'hb9, 8'hba, 8'hbb,
              8'hbc, 8'hbd, 8'hbe, 8'hbf: begin
                cmd_len <= 3'd2;
                state <= CMD;
              end
              8'hc0, 8'hc1, 8'hc2, 8'hc3,
              8'hc4, 8'hc5, 8'hc6, 8'hc7,
              8'hc8, 8'hc9, 8'hca, 8'hcb,
              8'hcc, 8'hcd, 8'hce, 8'hcf:
                if (din[3:0] == kbd_ctl_addr) begin
                  // adb kbd talk
                end
              8'hf0, 8'hf1, 8'hf2, 8'hf3,
              8'hf4, 8'hf5, 8'hf6, 8'hf7,
              8'hf8, 8'hf9, 8'hfa, 8'hfb,
              8'hfc, 8'hfd, 8'hfe, 8'hff:
                if (din[3:0] == kbd_ctl_addr) begin
                  // adb response packet
                end
            endcase

          end

          CMD: begin
            cmd_data[(cmd_len-1)*8+:8] <= din;

            // enough data
            if (cmd_len == 3'd1) begin

              cmd_len <= 3'd0;
              state <= IDLE;
              case (cmd)
                8'h04: adb_mode <= din | adb_mode;
                8'h05: adb_mode <= adb_mode & ~din;
                8'h06, 8'h07: begin // 31:24 23:16 15:8 din[7:0]
                  if (cmd[0]) adb_mode <= cmd_data[31:24] | adb_mode;
                  mouse_ctl_addr <= cmd_data[23:20];
                  kbd_ctl_addr <= cmd_data[19:16];
                  repeat_delay <= din[7] ? 8'd0 : (din[7:4]+1)*8'd15;
                  case (din[3:0])
                    4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6: repeat_rate <= cmd_data[3:0]+1;
                    4'd7: repeat_rate <= 8'd15;
                    4'd8: repeat_rate <= 8'd30;
                    4'd9: repeat_rate <= 8'd60;
                  endcase
                end
                8'h08: ram[cmd_data[15:8]] <= din;
                8'h09: begin
                  data <= { data[23:0], ram[{ din, cmd_data[15:8] }] };
                  pending_data <= 3'd1;
                end
                8'h11: ; // send keycode data[7:0]
                8'h12: ; // cmd 12
                8'h13: ; // cmd 13
                8'hb0, 8'hb1, 8'hb2, 8'hb3,
                8'hb4, 8'hb5, 8'hb6, 8'hb7,
                8'hb8, 8'hb9, 8'hba, 8'hbb,
                8'hbc, 8'hbd, 8'hbe, 8'hbf:
                  if (cmd[3:0] == kbd_ctl_addr) begin
                    // kbd stuff
                  end
                  else if (cmd[3:0] == mouse_ctl_addr) begin
                    // mouse stuff
                  end
              endcase

            end
            else begin
              cmd_len <= cmd_len - 3'd1;
            end
          end


        endcase

      end

    end

    8'h27: begin

      if (rw) begin
        dout <= {
          valid_mouse_data,
          mouse_int,
          pending_data > 0 ? 1'b1 : 1'b0, // valid data
          data_int,
          valid_kbd,
          kbd_int,
          mouse_coord,
          cmd_full
        };
      end
      else begin
        mouse_int <= din[6];
        data_int <= din[4];
        kbd_int <= din[2];
      end

    end

    8'h60, 8'h61, 8'h62, 8'h63: begin
      // joy num is addr[1:0]-2'd1
      dout <= 8'd0;
    end

    8'h64, 8'h65, 8'h66, 8'h67: begin
      // paddle num is addr[1:0]
      dout <= 8'd0;
    end

  endcase


end

endmodule
