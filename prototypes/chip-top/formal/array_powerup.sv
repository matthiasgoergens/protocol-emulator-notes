// Power-up determinism of the PE array (prototypes/chip-top README, "The PE array's reset"),
// the method of ../../formal/powerup/powerup.sv: two copies of the array start from independent,
// arbitrary register contents and get the same inputs on every clock. Clear is forced for the
// first clock. From the next clock on, every register of every PE and segment and every tap
// must be equal in both copies, at every clock: nothing the array does after reset depends on
// its flip-flops' power-up values.
module array_powerup (
    input clock, input clear_in,
    input mbx_wr, input [1:0] mbx_seg, input [1:0] mbx_sel, input [7:0] mbx_byte,
    input cfg_wr, input [1:0] cfg_seg, input [7:0] cfg_byte,
    input init_wr, input [1:0] init_seg, input [7:0] init_byte,
    input [15:0] fixed_d0, fixed_d1, fixed_d2, fixed_d3,
    input fixed_v0, fixed_v1, fixed_v2, fixed_v3
);
  reg started = 1'b0;  // the only initialised register
  always @(posedge clock) started <= 1'b1;
  wire clear = !started || clear_in;
`define COPY(x) \
  wire [`W-1:0] state_``x; wire seen_``x; \
  upe_array_pu copy_``x (.clock(clock), .clear(clear), .mbx_wr(mbx_wr), .mbx_seg(mbx_seg), \
    .mbx_sel(mbx_sel), .mbx_byte(mbx_byte), .cfg_wr(cfg_wr), .cfg_seg(cfg_seg), .cfg_byte(cfg_byte), \
    .init_wr(init_wr), .init_seg(init_seg), .init_byte(init_byte), .fixed_d0(fixed_d0), \
    .fixed_d1(fixed_d1), .fixed_d2(fixed_d2), .fixed_d3(fixed_d3), .fixed_v0(fixed_v0), \
    .fixed_v1(fixed_v1), .fixed_v2(fixed_v2), .fixed_v3(fixed_v3), .state(state_``x), .clear_seen(seen_``x));
  `COPY(a)
  `COPY(b)
  always @(*) if (started) assert (state_a == state_b);
endmodule
