/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * tt_um_chip_sram_probe: a minimal Tiny Tapeout block whose only job is to carry IHP's SRAM macros
 * RM_IHPSG13_1P_512x16_c2_bm_bist and RM_IHPSG13_1P_1024x8_c2_bm_bist through the sg13cmos5l
 * hardening flow (prototypes/chip-top/sram-macro/README.md). Every functional macro input is driven
 * by a flop that the host writes over the TT pins, and every data output is registered and readable
 * on uo_out, so the flow has real flop-to-macro and macro-to-flop paths to time.
 *
 * With SRAM_PROBE_NO_1024X8 defined (variants/config-512x16-only.json) the 1024x8 macro is left out.
 *
 * Host interface (all synchronous to clk):
 *   uio_in[3:0]  register index           ui_in  data byte
 *   uio_in[4]    write: while high, ui_in is written to register uio_in[3:0] on every clock
 *   uio_in[5]    go: a rising edge starts one macro access with the registered controls
 *   uio_in[7:6]  read select for uo_out: 0 DOUT512[7:0], 1 DOUT512[15:8], 2 DOUT1024, 3 status
 * Registers: 1 {sel1024, ren, wen, 3'b0, ADDR[9:8]} selects a macro and sets its controls;
 *            0 ADDR[7:0], 2 DIN[7:0], 3 DIN[15:8], 4 BM[7:0], 5 BM[15:8] go to the selected macro.
 *            The 1024x8 macro uses ADDR[9:0], DIN[7:0], BM[7:0]; the 512x16 ADDR[8:0], DIN, BM.
 * Each macro has its own input registers (a512/a1024 etc.), so every macro input net is short
 * and local. With one register set shared by both macros, each net ran ~300 um between them and
 * 22 macro pins missed the macros' 0.5952 ns max_transition at the slow corner (run2-both).
 * The BIST port of each macro is unused: A_BIST_EN low and every other A_BIST_* input low.
 * A_DLY is tied high, as the macro's model requires.
 */

`default_nettype none

module tt_um_chip_sram_probe (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  reg        sel1024;
  reg [8:0]  a512;   reg [15:0] d512;  reg [15:0] m512;  reg wen512,  ren512;
  reg [9:0]  a1024;  reg [7:0]  d1024; reg [7:0]  m1024; reg wen1024, ren1024;
  reg        go_q;      // uio_in[5] one clock late, for edge detection
  reg        men512, men1024;
  reg [15:0] dout512_q;
  reg [7:0]  dout1024_q;

  wire [15:0] dout512;
  wire [7:0]  dout1024;

  wire go = uio_in[5] & ~go_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      sel1024 <= 1'b0;
      a512  <= 9'd0;  d512  <= 16'd0; m512  <= 16'd0; wen512  <= 1'b0; ren512  <= 1'b0;
      a1024 <= 10'd0; d1024 <= 8'd0;  m1024 <= 8'd0;  wen1024 <= 1'b0; ren1024 <= 1'b0;
      go_q    <= 1'b0;
      men512  <= 1'b0;
      men1024 <= 1'b0;
      dout512_q  <= 16'd0;
      dout1024_q <= 8'd0;
    end else begin
      go_q <= uio_in[5];
      if (uio_in[4]) begin
        if (uio_in[3:0] == 4'd1) begin
          sel1024 <= ui_in[7];
          if (ui_in[7]) {ren1024, wen1024, a1024[9:8]} <= {ui_in[6:5], ui_in[1:0]};
          else          {ren512, wen512, a512[8]}      <= {ui_in[6:5], ui_in[0]};
        end else if (sel1024) begin
          case (uio_in[3:0])
            4'd0: a1024[7:0] <= ui_in;
            4'd2: d1024      <= ui_in;
            4'd4: m1024      <= ui_in;
            default: ;
          endcase
        end else begin
          case (uio_in[3:0])
            4'd0: a512[7:0]  <= ui_in;
            4'd2: d512[7:0]  <= ui_in;
            4'd3: d512[15:8] <= ui_in;
            4'd4: m512[7:0]  <= ui_in;
            4'd5: m512[15:8] <= ui_in;
            default: ;
          endcase
        end
      end
      // One-clock memory enable for the selected macro; the macro samples it on the next edge.
      men512  <= go & ~sel1024;
      men1024 <= go & sel1024;
      dout512_q  <= dout512;
      dout1024_q <= dout1024;
    end
  end

  RM_IHPSG13_1P_512x16_c2_bm_bist sram512 (
      .A_CLK(clk),
      .A_MEN(men512),
      .A_WEN(wen512),
      .A_REN(ren512),
      .A_ADDR(a512),
      .A_DIN(d512),
      .A_DLY(1'b1),
      .A_DOUT(dout512),
      .A_BM(m512),
      .A_BIST_CLK(1'b0),
      .A_BIST_EN(1'b0),
      .A_BIST_MEN(1'b0),
      .A_BIST_WEN(1'b0),
      .A_BIST_REN(1'b0),
      .A_BIST_ADDR(9'd0),
      .A_BIST_DIN(16'd0),
      .A_BIST_BM(16'd0)
  );

`ifndef SRAM_PROBE_NO_1024X8
  RM_IHPSG13_1P_1024x8_c2_bm_bist sram1024 (
      .A_CLK(clk),
      .A_MEN(men1024),
      .A_WEN(wen1024),
      .A_REN(ren1024),
      .A_ADDR(a1024),
      .A_DIN(d1024),
      .A_DLY(1'b1),
      .A_DOUT(dout1024),
      .A_BM(m1024),
      .A_BIST_CLK(1'b0),
      .A_BIST_EN(1'b0),
      .A_BIST_MEN(1'b0),
      .A_BIST_WEN(1'b0),
      .A_BIST_REN(1'b0),
      .A_BIST_ADDR(10'd0),
      .A_BIST_DIN(8'd0),
      .A_BIST_BM(8'd0)
  );
`else
  // keeps the 1024x8's registers observable when the macro is absent
  assign dout1024 = {men1024, wen1024, ren1024, ^a1024, ^d1024, ^m1024, 2'b0};
`endif

  wire [7:0] status = sel1024 ? {men1024, men512, 1'b1, ren1024, wen1024, 1'b0, a1024[9:8]}
                              : {men1024, men512, 1'b0, ren512, wen512, 2'b0, a512[8]};

  assign uo_out = (uio_in[7:6] == 2'd0) ? dout512_q[7:0]
                : (uio_in[7:6] == 2'd1) ? dout512_q[15:8]
                : (uio_in[7:6] == 2'd2) ? dout1024_q
                : status;
  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;

  wire _unused = &{ena, 1'b0};

endmodule

`default_nettype wire
