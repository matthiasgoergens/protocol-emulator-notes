/*
 * SPDX-License-Identifier: Apache-2.0
 * Port-only blackbox of IHP's RM_IHPSG13_1P_512x16_c2_bm_bist (IHP-Open-PDK 2bbec755,
 * ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_1P_512x16_c2_bm_bist.v, Apache-2.0), for synthesis and lint.
 * The flow reads it through the MACROS "nl" entry in config.json; the macro itself comes from the
 * PDK's GDS, LEF and Liberty files. No body: a body would be synthesised instead of the macro.
 * Port declarations copied from the PDK model. The practice of a port-only stub is
 * tt_um_urish_sram_test's and thomasgilbert481/tt_um_loom's.
 */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
(* blackbox *)
module RM_IHPSG13_1P_512x16_c2_bm_bist (
    A_CLK,
    A_MEN,
    A_WEN,
    A_REN,
    A_ADDR,
    A_DIN,
    A_DLY,
    A_DOUT,
    A_BM,
    A_BIST_CLK,
    A_BIST_EN,
    A_BIST_MEN,
    A_BIST_WEN,
    A_BIST_REN,
    A_BIST_ADDR,
    A_BIST_DIN,
    A_BIST_BM
);
    input A_CLK;
    input A_MEN;
    input A_WEN;
    input A_REN;
    input [8:0] A_ADDR;
    input [15:0] A_DIN;
    input A_DLY;
    output [15:0] A_DOUT;
    input [15:0] A_BM;
    input A_BIST_CLK;
    input A_BIST_EN;
    input A_BIST_MEN;
    input A_BIST_WEN;
    input A_BIST_REN;
    input [8:0] A_BIST_ADDR;
    input [15:0] A_BIST_DIN;
    input [15:0] A_BIST_BM;
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
