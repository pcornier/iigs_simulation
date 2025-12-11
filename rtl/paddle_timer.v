//-----------------------------------------------------------------------------
//
// Paddle Timer for Apple IIgs
// Simulates RC timing circuit for paddle/joystick analog inputs
//
// Uses 14MHz tick counter for wall-clock timing, independent of CPU speed.
// This ensures paddle timing works correctly whether the CPU is in fast mode
// (2.8MHz) or slow mode (1MHz).
//
//-----------------------------------------------------------------------------

module paddle_timer(
    input clk,
    input reset,
    input trigger,              // $C070 write - starts timing
    input [7:0] paddle_value,   // 0-255 from MiSTer
    input [31:0] tick_counter,  // 14MHz tick counter (wall-clock time)
    output reg timer_expired    // 0=still timing, 1=expired
);

// Calculate timeout in 14MHz ticks
// Real Apple II paddle timing: ~11.04 microseconds per paddle unit (at 1MHz)
// At 14.318 MHz: 11.04 µs * 14.318 = ~158 ticks per paddle unit
// Using 158 = 128 + 16 + 8 + 4 + 2 = (paddle << 7) + (paddle << 4) + (paddle << 3) + (paddle << 2) + (paddle << 1)
// Simplified: 158 ≈ 160 - 2 = (paddle << 5) * 5 - (paddle << 1)
// Or just use: paddle * 158
//
// Minimum timeout of ~28 ticks (2µs) ensures timer is active when first read
reg [31:0] trigger_tick;
wire [23:0] base_timeout = paddle_value * 24'd158;
wire [23:0] timeout_ticks = (base_timeout < 24'd28) ? 24'd28 : base_timeout;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        timer_expired <= 1'b1;
        trigger_tick <= 32'd0;
    end else if (trigger) begin
        timer_expired <= 1'b0;
        trigger_tick <= tick_counter;
    end else if (!timer_expired) begin
        if ((tick_counter - trigger_tick) >= {8'd0, timeout_ticks}) begin
            timer_expired <= 1'b1;
        end
    end
end

endmodule