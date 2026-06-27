//
// altddio_out.v -- minimal Verilator-friendly stub for the Altera altddio_out primitive,
// used only so rtl/sdram.sv can be compiled in a standalone simulation. The real primitive
// DDR-forwards the SDRAM clock to the pin; the behavioral chip model (sdram_sim_chip.sv)
// samples the controller's own `clk`, not SDRAM_CLK, so a trivial forward is sufficient here.
//
module altddio_out #(
    parameter extend_oe_disable    = "OFF",
    parameter intended_device_family= "NONE",
    parameter invert_output        = "OFF",
    parameter lpm_hint             = "UNUSED",
    parameter lpm_type             = "altddio_out",
    parameter oe_reg               = "UNREGISTERED",
    parameter power_up_high        = "OFF",
    parameter width                = 1
) (
    input  [width-1:0] datain_h,
    input  [width-1:0] datain_l,
    input              outclock,
    input              outclocken,
    input              aclr,
    input              aset,
    input              sclr,
    input              sset,
    input              oe,
    output [width-1:0] dataout
);
    // good enough for sim: present the clock level on the pin
    assign dataout = {width{outclock}};
endmodule
