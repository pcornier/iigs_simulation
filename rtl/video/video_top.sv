//
// Video Top Module for IIgs Emulation
//
// (c) 2023,2024 Ed Anuff <ed@a2fpga.com> 
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//
// Description:
//
// This module integrates the Apple II video controller and VGC (Video Graphics Controller)
// into a unified interface suitable for IIgs emulation. It handles Apple II standard video
// modes and Super High Resolution Graphics.
//

module video_top (
    input clk,
    input clk_vid,
    input ce_pix,
    input [9:0] H,
    input [8:0] V,
    output reg scanline_irq,
    output reg vbl_irq,
    output reg [7:0] R,
    output reg [7:0] G,
    output reg [7:0] B,
    output [22:0] video_addr,
    input [7:0] video_data,
    
    // Apple II video mode control
    input text_mode,
    input mixed_mode,
    input page2,
    input hires_mode,
    input an3,
    input store80,
    input col80,
    input altchar,
    
    // Color control
    input [3:0] text_color,
    input [3:0] background_color,
    input [3:0] border_color,
    input monochrome_mode,
    input monochrome_dhires_mode,
    
    // VGC/Super Hires control
    input shrg_mode,
    
    // Memory interface
    output [15:0] apple_video_addr,
    output apple_video_bank,
    output apple_video_rd,
    input [31:0] apple_video_data,
    
    output [12:0] vgc_address,
    output vgc_rd,
    input [31:0] vgc_data,
    
    // Additional control signals
    input gs_mode
);

    // Internal video signals
    wire [7:0] apple_video_r, apple_video_g, apple_video_b;
    wire [7:0] vgc_video_r, vgc_video_g, vgc_video_b;
    wire apple_video_active, vgc_active;

    // Apple II Video Controller
    apple_video apple_video_inst (
        .clk_pixel(clk_vid),
        .gs_mode(gs_mode),
        .screen_x_i(H),
        .screen_y_i({1'b0, V}),
        .video_address_o(apple_video_addr),
        .video_bank_o(apple_video_bank),
        .video_rd_o(apple_video_rd),
        .video_data_i(apple_video_data),
        .video_active_o(apple_video_active),
        .video_r_o(apple_video_r),
        .video_g_o(apple_video_g),
        .video_b_o(apple_video_b),
        .text_mode(text_mode),
        .mixed_mode(mixed_mode),
        .page2(page2),
        .hires_mode(hires_mode),
        .an3(an3),
        .store80(store80),
        .col80(col80),
        .altchar(altchar),
        .video_control_enable(1'b0),
        .text_color(text_color),
        .background_color(background_color),
        .border_color(border_color),
        .monochrome_mode(monochrome_mode),
        .monochrome_dhires_mode(monochrome_dhires_mode),
        .shrg_mode(shrg_mode)
    );

    // VGC (Super High Resolution Graphics)
    vgc vgc_inst (
        .clk_pixel(clk_vid),
        .cx_i(H),
        .cy_i({1'b0, V}),
        .apple_vga_r_i(apple_video_r),
        .apple_vga_g_i(apple_video_g),
        .apple_vga_b_i(apple_video_b),
        .vgc_vga_r_o(vgc_video_r),
        .vgc_vga_g_o(vgc_video_g),
        .vgc_vga_b_o(vgc_video_b),
        .R_o(),  // Not used - VGC outputs through vgc_vga_*_o
        .G_o(),
        .B_o(),
        .vgc_active_o(vgc_active),
        .vgc_address_o(vgc_address),
        .vgc_rd_o(vgc_rd),
        .vgc_data_i(vgc_data),
        .shrg_mode(shrg_mode),
        .border_color(border_color),
        .video_control_enable(1'b0)
    );

    // Video address generation - combine both controllers
    wire [22:0] apple_addr_extended = {7'b0, apple_video_addr};
    wire [22:0] vgc_addr_extended = {10'b0, vgc_address};
    assign video_addr = vgc_active ? vgc_addr_extended : apple_addr_extended;

    // Output multiplexing - VGC takes priority when active
    always @(posedge clk_vid) begin
        R <= vgc_video_r;
        G <= vgc_video_g;
        B <= vgc_video_b;
    end

    // IRQ generation - basic implementation
    reg [9:0] prev_v;
    reg [9:0] prev_h;
    
    always @(posedge clk_vid) begin
        prev_v <= {1'b0, V};
        prev_h <= H;
        
        // VBL IRQ at start of vertical blanking
        vbl_irq <= (prev_v < 400) && ({1'b0, V} >= 400);
        
        // Scanline IRQ - could be configurable
        scanline_irq <= 1'b0;  // Disabled for now
    end

endmodule