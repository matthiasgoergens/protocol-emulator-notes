// Event-driven check of the real-clock stage (multiphase_stage.v, four clock inputs) against the
// stage's reference model, re-implemented here independently of the OCaml test:
//   output: after core edge E_(k+1) + p/4 the pin equals N_k[p], N_k = nibble presented from E_k;
//   input: the samples word latched at E_(j+2) holds the pads at E_j + p/4.
// Times in ps. The core's nibble changes CLK_Q after each ph0 edge, like a register output. Pads
// change half-way between sampling edges. Pins are checked at the middle of each
// quarter. SKEW1..3 delay the phase clocks (can be negative) to probe functional skew tolerance.
`timescale 1ps/1ps
module tb;
  parameter integer PERIOD = 16000;
  parameter integer SKEW1 = 0, SKEW2 = 0, SKEW3 = 0;
  parameter integer CLK_Q = 300;
  parameter integer CLOCKS = 20000;
  localparam integer Q = PERIOD / 4;

  reg ph0 = 0, ph1 = 0, ph2 = 0, ph3 = 0, clear = 1;
  reg [7:0] sub = 0;
  reg [1:0] oe = 0, pads = 0;
  wire [1:0] pin, pin_oe;
  wire [7:0] samples;
  multiphase_stage dut (.pads(pads), .oe(oe), .ph3(ph3), .ph2(ph2), .ph1(ph1), .clear(clear), .ph0(ph0),
                        .sub(sub), .pin(pin), .pin_oe(pin_oe), .samples(samples));

  // clocks: ph_p rises at k*PERIOD + p*Q + SKEWp
  always begin ph0 = 1; #(PERIOD/2); ph0 = 0; #(PERIOD/2); end
  initial begin #(Q + SKEW1); forever begin ph1 = 1; #(PERIOD/2); ph1 = 0; #(PERIOD/2); end end
  initial begin #(2*Q + SKEW2); forever begin ph2 = 1; #(PERIOD/2); ph2 = 0; #(PERIOD/2); end end
  initial begin #(3*Q + SKEW3); forever begin ph3 = 1; #(PERIOD/2); ph3 = 0; #(PERIOD/2); end end

  reg [7:0] nib_hist [0:CLOCKS+8];     // nib_hist[k] = N_k
  reg [1:0] pad_hist [0:4*CLOCKS+32];  // pads around the sampling edge of quarter 4j+p
  integer j, p, errors_out = 0, errors_in = 0, checks_out = 0, checks_in = 0, seed = 7, toggles = 0;
  reg [1:0] lastpin = 0, want;
  reg [7:0] want_s;
  initial begin
    for (j = 0; j < CLOCKS + 8; j = j + 1) nib_hist[j] = 0;
    for (j = 0; j < 4 * CLOCKS + 32; j = j + 1) pad_hist[j] = 0;
    for (j = 0; j < CLOCKS; j = j + 1) begin
      @(posedge ph0);                      // E_j
      #(CLK_Q);
      if (j == 4) clear = 0;
      if (j >= 4) nib_hist[j] = $random(seed);
      sub = nib_hist[j];
      oe = 2'b11;
      // samples latched at E_j hold the pads of clock j - 2
      if (j >= 8) begin
        for (p = 0; p < 4; p = p + 1) begin
          want_s[p] = pad_hist[4*(j-2)+p][0];
          want_s[4+p] = pad_hist[4*(j-2)+p][1];
        end
        checks_in = checks_in + 1;
        if (samples !== want_s) begin
          errors_in = errors_in + 1;
          if (errors_in <= 5) $display("in mismatch at clock %0d: samples %b want %b", j, samples, want_s);
        end
      end
      for (p = 0; p < 4; p = p + 1) begin
        if (p == 0) #(Q/2 - CLK_Q);
        // middle of quarter p of clock j: check the pin against N_(j-1)[p]
        if (j >= 6) begin
          want[0] = nib_hist[j-1][p];
          want[1] = nib_hist[j-1][4+p];
          checks_out = checks_out + 1;
          if (pin !== want) begin
            errors_out = errors_out + 1;
            if (errors_out <= 5) $display("out mismatch clock %0d quarter %0d: pin %b want %b", j, p, pin, want);
          end
          if (pin !== lastpin) toggles = toggles + 1;
          lastpin = pin;
        end
        // at E_j + p*Q + Q/2: new pads for the sampling edge at E_j + (p+1)*Q
        pads = $random(seed);
        pad_hist[4*j+p+1] = pads;
        if (p < 3) #(Q);
      end
    end
    $display("PERIOD %0d ps SKEW %0d %0d %0d ps: %0d output quarters checked, %0d wrong, %0d pin changes; %0d sample words checked, %0d wrong",
             PERIOD, SKEW1, SKEW2, SKEW3, checks_out, errors_out, toggles, checks_in, errors_in);
    $finish;
  end
endmodule
