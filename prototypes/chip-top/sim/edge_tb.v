// The edge-phase test (bin/edge_phase.ml) in an event-driven simulator: replays the stimulus that
// edge_phase.exe wrote, one line per half clock, "EDGE RST_N PADS DCHIP" (EDGE 1 for the rising
// edge, PADS = {uio_in, ui_in} in hex, DCHIP 1 where the data lines uio[3:0] are the chip's own
// outputs, as the host has released them), and writes the outputs after every edge,
// {uio_oe, uio_out, uo_out} in hex, for edge_phase.exe replay.
//
// The clock period is 20 ns. Inputs change 5 ns before each edge: at 3T/4 of the previous clock for
// a rising edge, at T/4 for a falling one, which is where edge_phase.ml places a pad's toggles.
// The outputs are read 4 ns after the edge. Works on the RTL (chip_tt.v) and on the hardened
// gate netlist alike; both get IHP's functional SRAM models.
`timescale 1ns / 1ps
`default_nettype none

module edge_tb;
  reg clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
  reg [7:0] ui_in = 8'h00, uio_in = 8'h00;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_chip_top dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
      .ena(ena), .clk(clk), .rst_n(rst_n));

  // Plants (sim/nl_plants.py): a plantable netlist clocks falling-edge flop k from
  // (its clock ^ plant[k]); +plant=k puts it on the rising edge.
  reg [63:0] plant = 64'd0;
  integer pk;
  initial if ($value$plusargs("plant=%d", pk)) plant[pk] = 1'b1;

  integer fd, fo, n, edge_, rst, pads, dchip, halves;
  reg [8*256-1:0] trace_file;
  initial begin
    fd = $fopen(`STIM, "r");
    if (!$value$plusargs("trace=%s", trace_file)) trace_file = `TRACE;
    fo = $fopen(trace_file, "w");
    if (fd == 0 || fo == 0) begin $display("edge_tb: cannot open the files"); $finish; end
    halves = 0;
    #20;
    forever begin
      n = $fscanf(fd, "%d %d %h %d\n", edge_, rst, pads, dchip);
      if (n != 4) begin
        $display("edge_tb: %0d half clocks", halves);
        $fclose(fo);
        $finish;
      end
      rst_n = rst[0];
      ui_in = pads[7:0];
      uio_in = {pads[15:12], dchip[0] ? uio_out[3:0] : pads[11:8]};
      #5 clk = edge_[0];
      #4 $fdisplay(fo, "%06x", {uio_oe, uio_out, uo_out});
      #1 halves = halves + 1;
    end
  end
endmodule
