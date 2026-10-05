// Power-up determinism of the ISA v2 core (README.md, section 5). After MarcosAsh's
// formal/powerup.sby (github.com/MarcosAsh/protocol-emulator, Apache-2.0); idea only, this file is
// our own.
//
// Two copies of deadline_sequencer_v2 start from independent, arbitrary register contents (no
// register of the core has an initial value; SymbiYosys treats such registers as free at step 0).
// Both get the same inputs on every clock, including clear. Clear is forced high for the first
// RESET_CLOCKS clocks. From then on, every output must be the same in both copies at every
// clock. That is exactly "every register that can reach an output is reset": a register left
// out of the clear may differ between the copies, and the proof fails only if the difference
// can reach a pin.
//
// The memories are outside the core, as on the chip:
// - programme store: one-clock synchronous read. Each copy's word is the store's output for the
//   address that copy presented on the previous clock. The model gives both copies the same word
//   when they presented the same address, and independent words otherwise, so the store's
//   contents are the same in both copies but otherwise arbitrary (they may even change; that only
//   adds behaviours). The store's output latch at power-up is as arbitrary as the addresses.
// - data bank: the same, keyed on the previous clock's read strobe and address.
//
// Data outputs are compared only while their strobe says they carry data (host_out and host_tag
// with host_out_valid, port_out_data with any port_out_valid, bank_addr with bank_we or bank_re,
// bank_wdata with bank_we, fine_out with fine_valid), as a receiver would see them. Pins, output
// enables, quarter-clock levels, strobes, the fetch address and cfg_out are compared raw.

module powerup #(parameter RESET_CLOCKS = 1) (
    input clock,
    input clear_in,
    input [15:0] imem_word, imem_word_other,
    input [7:0] bank_byte, bank_byte_other,
    input [15:0] flags,
    input [3:0] port_out_ready,
    input [31:0] pin_in4,
    input [7:0] pin_in,
    input [7:0] host_in,
    input host_in_valid,
    input [7:0] port_in3, port_in2, port_in1, port_in0,
    input [3:0] port_in_valid,
    input [31:0] boot_pc,
    input [7:0] ctl_pc,
    input [7:0] boot_page,
    input [1:0] ctl_page,
    input [1:0] ctl_thread,
    input ctl_valid
);
  // the only initialised register: counts the forced reset clocks
  reg [1:0] n = 2'd0;
  always @(posedge clock) if (n != 2'd3) n <= n + 2'd1;
  wire started = n >= RESET_CLOCKS;
  wire clear = !started || clear_in;

  wire [9:0] imem_addr_a, imem_addr_b, bank_addr_a, bank_addr_b;
  wire bank_re_a, bank_re_b;
  // memory side, per copy, arbitrary at power-up
  reg [9:0] fetched_a, fetched_b, read_addr_a, read_addr_b;
  reg read_a, read_b;
  always @(posedge clock) begin
    fetched_a <= imem_addr_a; fetched_b <= imem_addr_b;
    read_a <= bank_re_a; read_b <= bank_re_b;
    read_addr_a <= bank_addr_a; read_addr_b <= bank_addr_b;
  end
  wire [15:0] imem_a = imem_word;
  wire [15:0] imem_b = fetched_a == fetched_b ? imem_word : imem_word_other;
  wire [7:0] rdata_a = bank_byte;
  wire [7:0] rdata_b = read_a && read_b && read_addr_a == read_addr_b ? bank_byte : bank_byte_other;

`define CORE(x) \
  wire [7:0] pin_out_``x, pin_oe_``x, host_out_``x, port_out_data_``x, bank_wdata_``x, fine_out_``x; \
  wire [31:0] pin_sub_``x, cfg_out_``x; \
  wire [2:0] host_tag_``x; \
  wire [3:0] port_out_valid_``x, port_in_ready_``x; \
  wire host_out_valid_``x, host_in_ready_``x, bank_we_``x, fine_valid_``x; \
  deadline_sequencer_v2 core_``x ( \
    .flags(flags), .port_out_ready(port_out_ready), .bank_rdata(rdata_``x), .pin_in4(pin_in4), \
    .pin_in(pin_in), .host_in(host_in), .host_in_valid(host_in_valid), \
    .port_in3(port_in3), .port_in2(port_in2), .port_in1(port_in1), .port_in0(port_in0), \
    .port_in_valid(port_in_valid), .boot_pc(boot_pc), .ctl_pc(ctl_pc), .imem_data(imem_``x), \
    .boot_page(boot_page), .ctl_page(ctl_page), .clear(clear), .clock(clock), \
    .ctl_thread(ctl_thread), .ctl_valid(ctl_valid), \
    .imem_addr(imem_addr_``x), .pin_out(pin_out_``x), .pin_oe(pin_oe_``x), .pin_sub(pin_sub_``x), \
    .host_out(host_out_``x), .host_tag(host_tag_``x), .host_out_valid(host_out_valid_``x), \
    .host_in_ready(host_in_ready_``x), .port_out_data(port_out_data_``x), \
    .port_out_valid(port_out_valid_``x), .port_in_ready(port_in_ready_``x), \
    .bank_addr(bank_addr_``x), .bank_we(bank_we_``x), .bank_re(bank_re_``x), \
    .bank_wdata(bank_wdata_``x), .fine_out(fine_out_``x), .fine_valid(fine_valid_``x), \
    .cfg_out(cfg_out_``x));

  `CORE(a)
  `CORE(b)

  // one assertion per output group, so that a failure names what differs
  always @(*) if (started) begin
    pins:      assert (pin_out_a == pin_out_b && pin_oe_a == pin_oe_b && pin_sub_a == pin_sub_b);
    fetch:     assert (imem_addr_a == imem_addr_b);
    host:      assert (host_out_valid_a == host_out_valid_b && host_in_ready_a == host_in_ready_b
                       && (!host_out_valid_a || (host_out_a == host_out_b && host_tag_a == host_tag_b)));
    ports:     assert (port_out_valid_a == port_out_valid_b && port_in_ready_a == port_in_ready_b
                       && (port_out_valid_a == 4'd0 || port_out_data_a == port_out_data_b));
    bank:      assert (bank_we_a == bank_we_b && bank_re_a == bank_re_b
                       && (!(bank_we_a || bank_re_a) || bank_addr_a == bank_addr_b)
                       && (!bank_we_a || bank_wdata_a == bank_wdata_b));
    fine:      assert (fine_valid_a == fine_valid_b && (!fine_valid_a || fine_out_a == fine_out_b));
    cfg:       assert (cfg_out_a == cfg_out_b);
    // a control for the per-property report: an implication whose antecedent (the output
    // enables differ) the other assertions rule out, so it holds vacuously and must be
    // reported VACUOUS, never PROVED
    vacuity_control: assert (pin_oe_a == pin_oe_b || pin_out_a == pin_out_b);
  end

  // Antecedent covers, one per assertion (<name>_ante), for the per-property report
  // (../sby_report.py): after the reset and without another clear, the outputs the assertion
  // compares actually do something. An assertion whose antecedent is unreachable is VACUOUS.
  reg quiet = 1'b1;   // no clear since the forced reset
  always @(posedge clock) if (started && clear_in) quiet <= 1'b0;
  reg [9:0] fetch_before;
  always @(posedge clock) fetch_before <= imem_addr_a;
  always @(*) if (started && quiet && !clear_in) begin
    pins_ante:  cover (pin_oe_a != 8'd0);
    fetch_ante: cover (n == 2'd3 && imem_addr_a != fetch_before);
    host_ante:  cover (host_out_valid_a);
    ports_ante: cover (port_out_valid_a != 4'd0);
    bank_ante:  cover (bank_we_a);
    fine_ante:  cover (fine_valid_a);
    cfg_ante:   cover (cfg_out_a != 32'd0);
    vacuity_control_ante: cover (pin_oe_a != pin_oe_b);
  end
endmodule
