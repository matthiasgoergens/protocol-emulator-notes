/*
 * SPDX-License-Identifier: Apache-2.0
 * AXI4-Lite slave for fpga_bench's register bus. One transaction at a time; a write takes the
 * address and data in either order; each accepted read gives exactly one bus_re pulse, which
 * matters because some reads advance an address. Only full-word writes (all four strobes) reach
 * the bus: the registers have side effects and no byte lanes, so a partial write is acknowledged
 * and ignored. Responses are always OKAY.
 * The s_axi_* names let Vivado infer the interface when this module is added to a block design.
 */

`default_nettype none

module fpga_axil (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [ 7:0] s_axi_awaddr,
    input  wire [ 2:0] s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready = 1'b0,
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready = 1'b0,
    output wire [ 1:0] s_axi_bresp,
    output reg         s_axi_bvalid = 1'b0,
    input  wire        s_axi_bready,
    input  wire [ 7:0] s_axi_araddr,
    input  wire [ 2:0] s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready = 1'b0,
    output wire [31:0] s_axi_rdata,
    output wire [ 1:0] s_axi_rresp,
    output reg         s_axi_rvalid = 1'b0,
    input  wire        s_axi_rready,
    // to fpga_bench
    output reg  [ 7:0] bus_addr = 8'd0,
    output reg  [31:0] bus_wdata = 32'd0,
    output reg         bus_we = 1'b0,
    output reg         bus_re = 1'b0,
    input  wire [31:0] bus_rdata
);
  assign s_axi_bresp = 2'b00;
  assign s_axi_rresp = 2'b00;
  assign s_axi_rdata = bus_rdata;          // held: fpga_bench updates it only on bus_re

  reg have_aw = 1'b0, have_w = 1'b0;
  reg [7:0] aw = 8'd0;
  reg [31:0] wd = 32'd0;
  reg full = 1'b0;                         // the write had all four strobes
  reg rd_wait = 1'b0;

  always @(posedge s_axi_aclk) begin
    bus_we <= 1'b0;
    bus_re <= 1'b0;
    s_axi_awready <= 1'b0;
    s_axi_wready <= 1'b0;
    s_axi_arready <= 1'b0;
    if (!s_axi_aresetn) begin
      have_aw <= 1'b0;
      have_w <= 1'b0;
      s_axi_bvalid <= 1'b0;
      s_axi_rvalid <= 1'b0;
      rd_wait <= 1'b0;
    end else begin
      // write: collect address and data, then one bus_we and the response
      if (!have_aw && s_axi_awvalid && !s_axi_awready && !s_axi_bvalid) begin
        s_axi_awready <= 1'b1;
        have_aw <= 1'b1;
        aw <= s_axi_awaddr;
      end
      if (!have_w && s_axi_wvalid && !s_axi_wready && !s_axi_bvalid) begin
        s_axi_wready <= 1'b1;
        have_w <= 1'b1;
        wd <= s_axi_wdata;
        full <= &s_axi_wstrb;
      end
      if (have_aw && have_w && !s_axi_bvalid && !rd_wait && !bus_re) begin
        bus_addr <= {aw[7:2], 2'b00};
        bus_wdata <= wd;
        bus_we <= full;
        have_aw <= 1'b0;
        have_w <= 1'b0;
        s_axi_bvalid <= 1'b1;
      end else if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

      // read: one bus_re, the data a clock later
      if (s_axi_arvalid && !s_axi_arready && !rd_wait && !s_axi_rvalid && !(have_aw && have_w)) begin
        s_axi_arready <= 1'b1;
        bus_addr <= {s_axi_araddr[7:2], 2'b00};
        bus_re <= 1'b1;
        rd_wait <= 1'b1;
      end else if (rd_wait && !bus_re) begin
        rd_wait <= 1'b0;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
    end
  end

  wire _unused = &{1'b0, s_axi_awprot, s_axi_arprot};
endmodule
