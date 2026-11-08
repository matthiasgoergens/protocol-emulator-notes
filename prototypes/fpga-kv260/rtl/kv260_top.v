/*
 * SPDX-License-Identifier: Apache-2.0
 * Top level for the KV260: the block design (the Zynq processor system and kv260_core, built by
 * ../vivado/build.tcl, which also generates kv260_bd_wrapper) and the carrier's Pmod connector.
 *
 * Pmod pins (../constraints/kv260.xdc):
 *   1 uo_out[0]  UART TX         7 uio[6]  I2C SDA, open drain
 *   2 uo_out[1]  SPI SCLK        8 uio[7]  I2C SCL, open drain
 *   3 uo_out[2]  SPI MOSI        9 ui_in[0], when UI_MASK bit 0 is set
 *   4 uo_out[3]  SPI CS         10 heartbeat: toggles every 0.5 s at 60 MHz
 * (the UART, SPI and I2C demo's pins; other demos may use them differently)
 */

`default_nettype none

module kv260_top (
    output wire pmod1,
    output wire pmod2,
    output wire pmod3,
    output wire pmod4,
    inout  wire pmod7,
    inout  wire pmod8,
    input  wire pmod9,
    output wire pmod10,
    output wire fan_en_b
);
  wire [7:0] uo_out;
  wire [1:0] uio67_out, uio67_oe, uio67_in;
  wire heartbeat;

  kv260_bd_wrapper bd (
      .uo_out(uo_out), .uio67_out(uio67_out), .uio67_oe(uio67_oe), .uio67_in(uio67_in),
      .ui_ext({7'd0, pmod9}), .heartbeat(heartbeat)
  );

  assign {pmod4, pmod3, pmod2, pmod1} = uo_out[3:0];
  // where the chip enables uio[7:6] it drives the pin; elsewhere the pin floats to the pull-up
  assign pmod7 = uio67_oe[0] ? uio67_out[0] : 1'bz;
  assign pmod8 = uio67_oe[1] ? uio67_out[1] : 1'bz;
  assign uio67_in = {pmod8, pmod7};
  assign pmod10 = heartbeat;
  // the fan at full speed: nothing in this design controls it
  assign fan_en_b = 1'b0;
endmodule
