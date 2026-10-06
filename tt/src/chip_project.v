/*
 * Copyright (c) 2026 Matthias Goergens
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper of the combined chip (prototypes/chip-top). Port list and file layout follow
 * TinyTapeout/ttihp-verilog-template (Apache-2.0).
 *
 * chip_tt.v is build output, never committed: generated from prototypes/chip-top's Hardcaml by
 * ../scripts/regen_chip.sh. It holds the core, the four-phase pin stage on both clock edges and
 * the reset synchroniser; this file only adds Tiny Tapeout's exact port list (Hardcaml leaves out
 * the unused [ena]).
 *
 * Pins (prototypes/chip-top/README.md, "Port map"): ui_in general inputs; uo_out general outputs;
 * uio[3:0] host link data, uio[4] strobe, uio[5] read request, uio[6], uio[7] general pins with
 * output enable.
 */

`default_nettype none

module tt_um_chip_top (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  chip_tt chip (
      .ui_in(ui_in),
      .uio_in(uio_in),
      .clk(clk),
      .rst_n(rst_n),
      .uo_out(uo_out),
      .uio_out(uio_out),
      .uio_oe(uio_oe)
  );

  wire _unused = &{ena, 1'b0};

endmodule
