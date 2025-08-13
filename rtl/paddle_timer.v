//-----------------------------------------------------------------------------
//
// Paddle Timer for Apple IIgs
// Simulates RC timing circuit for paddle/joystick analog inputs
//
//-----------------------------------------------------------------------------

module paddle_timer(
    input clk,
    input reset,
    input trigger,              // $C070 write - starts timing
    input [7:0] paddle_value,   // 0-255 from MiSTer
    input [23:0] cycle_counter, // CPU cycle counter (wider for safety)
    output reg timer_expired    // 0=still timing, 1=expired
);

// Calculate timeout: paddle_value * 11.04 CPU cycles
// This simulates the RC discharge time of real paddles
reg [23:0] trigger_cycle;
wire [19:0] timeout_cycles = (paddle_value * 20'd11) + (paddle_value >> 2);

always @(posedge clk or posedge reset) begin
    if (reset) begin
        timer_expired <= 1'b1;
        trigger_cycle <= 24'd0;
    end else if (trigger) begin
        timer_expired <= 1'b0;
        trigger_cycle <= cycle_counter;
    end else if (!timer_expired) begin
        if ((cycle_counter - trigger_cycle) >= {4'd0, timeout_cycles}) begin
            timer_expired <= 1'b1;
        end
    end
end

endmodule