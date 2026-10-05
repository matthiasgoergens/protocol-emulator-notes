/*
 * Copyright (c) 2026 Matthias Goergens
 * SPDX-License-Identifier: Apache-2.0
 *
 * Harness wrapper: port list and file layout follow TinyTapeout/ttihp-verilog-template (Apache-2.0).
 *
 * This wraps the ISA v2 deadline sequencer (deadline_sequencer_v2.v, generated from Hardcaml, see
 * ../scripts/regen.sh) so that the Tiny Tapeout flow and a cocotb test can drive it. It is a
 * HARNESS PLACEHOLDER, not the chip's final top level: the programme store is 64 x 16-bit
 * registers loaded serially (the real design uses the 512 x 16 SRAM macro), the data bank,
 * mailbox ports and flag inputs are tied off, and only 8 of the 32 core pin-input bits are wired.
 *
 * Pins:
 *   ui_in[7:0]   pin_in   the sequencer's eight pins, as inputs
 *   uo_out[7:0]  pin_out  the sequencer's eight pin outputs (pin_oe is not brought out)
 *   uio_in[0]    load data bit
 *   uio_in[1]    load strobe: while high, each clock shifts uio_in[0] into a 16-bit shift register,
 *                MSB first; after 16 strobed clocks the word is written at the load address, which
 *                then increments (it restarts at 0 on reset)
 *   uio_in[2]    run: the sequencer is held in clear while low
 *   uio_out, uio_oe  all zero (uio pins are inputs)
 */

`default_nettype none

module tt_um_seqv2 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire load_bit = uio_in[0];
  wire load_strobe = uio_in[1];
  wire run = uio_in[2];

  // Programme store: written by the loader, read with one clock of latency as the core expects.
  reg [15:0] mem[0:63];
  reg [15:0] shift;
  reg [3:0] nbits;
  reg [5:0] waddr;
  reg [15:0] imem_data;
  wire [9:0] imem_addr;
  wire [15:0] shift_next = {shift[14:0], load_bit};

  always @(posedge clk) begin
    if (!rst_n) begin
      nbits <= 4'd0;
      waddr <= 6'd0;
      shift <= 16'd0;
    end else if (load_strobe) begin
      shift <= shift_next;
      nbits <= nbits + 4'd1;
      if (nbits == 4'd15) begin
        mem[waddr] <= shift_next;
        waddr <= waddr + 6'd1;
      end
    end
    imem_data <= mem[imem_addr[5:0]];
  end

  wire [7:0] pin_oe_unused;
  wire [31:0] pin_sub_unused;
  wire [7:0] host_out_unused;
  wire [2:0] host_tag_unused;
  wire host_out_valid_unused;
  wire host_in_ready_unused;
  wire [7:0] port_out_data_unused;
  wire [3:0] port_out_valid_unused;
  wire [3:0] port_in_ready_unused;
  wire [9:0] bank_addr_unused;
  wire bank_we_unused;
  wire bank_re_unused;
  wire [7:0] bank_wdata_unused;
  wire [7:0] fine_out_unused;
  wire fine_valid_unused;
  wire [31:0] cfg_out_unused;

  deadline_sequencer_v2 core (
      .flags(16'd0),
      .port_out_ready(4'd0),
      .bank_rdata(8'd0),
      .pin_in4(32'd0),
      .pin_in(ui_in),
      .host_in(8'd0),
      .host_in_valid(1'b0),
      .port_in3(8'd0),
      .port_in2(8'd0),
      .port_in1(8'd0),
      .port_in0(8'd0),
      .port_in_valid(4'd0),
      .boot_pc(32'd0),
      .ctl_pc(8'd0),
      .imem_data(imem_data),
      .boot_page(8'd0),
      .ctl_page(2'd0),
      .clear(!rst_n || !run),
      .clock(clk),
      .ctl_thread(2'd0),
      .ctl_valid(1'b0),
      .imem_addr(imem_addr),
      .pin_out(uo_out),
      .pin_oe(pin_oe_unused),
      .pin_sub(pin_sub_unused),
      .host_out(host_out_unused),
      .host_tag(host_tag_unused),
      .host_out_valid(host_out_valid_unused),
      .host_in_ready(host_in_ready_unused),
      .port_out_data(port_out_data_unused),
      .port_out_valid(port_out_valid_unused),
      .port_in_ready(port_in_ready_unused),
      .bank_addr(bank_addr_unused),
      .bank_we(bank_we_unused),
      .bank_re(bank_re_unused),
      .bank_wdata(bank_wdata_unused),
      .fine_out(fine_out_unused),
      .fine_valid(fine_valid_unused),
      .cfg_out(cfg_out_unused)
  );

  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;

  // List all unused inputs and outputs to prevent warnings
  wire _unused = &{ena, uio_in[7:3], pin_oe_unused, pin_sub_unused, host_out_unused, host_tag_unused,
                   host_out_valid_unused, host_in_ready_unused, port_out_data_unused,
                   port_out_valid_unused, port_in_ready_unused, bank_addr_unused, bank_we_unused,
                   bank_re_unused, bank_wdata_unused, fine_out_unused, fine_valid_unused,
                   cfg_out_unused, 1'b0};

endmodule
