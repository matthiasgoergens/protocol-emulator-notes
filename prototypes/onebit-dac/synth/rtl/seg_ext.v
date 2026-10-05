// The array-level logic the onebit-dac additions E1 and E2 add, for an area estimate only
// (the same logic as sim/upe_rtl.ml's segregs and lane-loop mux, written out by hand for
// four segments). Not used by the simulations.
module seg_ext (
  input clk,
  input mbx_wr, input [1:0] mbx_seg, input [1:0] mbx_sel, input [7:0] mbx_byte,
  input [31:0] flo_all,          // the existing low-byte feed registers, 4 x 8
  input [31:0] fhi_all,          // the existing high-byte feed registers
  input [3:0] hi_write,          // the existing "high byte written" strobes
  input [11:0] src_all,          // the existing 3-bit source fields
  input [3:0] lane_loop,         // the new control bit 6 per segment
  input [3:0] end_lane,          // the lane registers of the four segment ends
  input [3:0] alane_in,          // the existing lane at each segment start
  output [63:0] word_all,        // the feed word presented to each segment's first PE
  output [3:0] fv_all,           // the feed valid
  output [3:0] alane_out
);
  genvar j;
  generate for (j = 0; j < 4; j = j + 1) begin : s
    wire mine = mbx_wr && mbx_seg == j;
    reg [7:0] rep, cnt; reg [15:0] fw; reg fv;
    wire repon = rep != 0;
    wire tick = repon && cnt == rep - 8'd1;
    always @(posedge clk) begin
      if (mine && mbx_sel == 2'd3) rep <= mbx_byte;
      cnt <= (mine && mbx_sel == 2'd3) ? 8'd0 : (repon ? (tick ? 8'd0 : cnt + 8'd1) : cnt);
      if (mine && mbx_sel == 2'd1) fw <= {mbx_byte, flo_all[8*j +: 8]};
      fv <= repon ? tick : hi_write[j];
    end
    assign word_all[16*j +: 16] = repon ? fw : {fhi_all[8*j +: 8], flo_all[8*j +: 8]};
    assign fv_all[j] = fv;
  end endgenerate
  // E1: the end of the joined run starting at each segment
  wire j1 = src_all[5:3] == 3'd0, j2 = src_all[8:6] == 3'd0, j3 = src_all[11:9] == 3'd0;
  wire e3 = end_lane[3];
  wire e2 = j3 ? e3 : end_lane[2];
  wire e1 = j2 ? e2 : end_lane[1];
  wire e0 = j1 ? e1 : end_lane[0];
  assign alane_out = { lane_loop[3] ? e3 : alane_in[3], lane_loop[2] ? e2 : alane_in[2],
                       lane_loop[1] ? e1 : alane_in[1], lane_loop[0] ? e0 : alane_in[0] };
endmodule
