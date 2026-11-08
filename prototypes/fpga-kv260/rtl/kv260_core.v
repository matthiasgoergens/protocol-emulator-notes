/*
 * SPDX-License-Identifier: Apache-2.0
 * The test bench with its AXI4-Lite port: the module that goes into the Vivado block design as a
 * module reference (../vivado/build.tcl), next to the Zynq processor system. Its AXI clock is the
 * chip's clock (pl_clk0, set to 60 MHz), so there is one clock domain.
 *
 * The pins stay as separate in, out and enable signals here; kv260_top.v turns them into the
 * Pmod connector's pads.
 */

`default_nettype none

module kv260_core (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [ 7:0] s_axi_awaddr,
    input  wire [ 2:0] s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [ 1:0] s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [ 7:0] s_axi_araddr,
    input  wire [ 2:0] s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [ 1:0] s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [ 7:0] uo_out,
    output wire [ 1:0] uio67_out,
    output wire [ 1:0] uio67_oe,
    input  wire [ 1:0] uio67_in,
    input  wire [ 7:0] ui_ext,
    output wire        heartbeat
);
  wire [7:0] bus_addr;
  wire [31:0] bus_wdata, bus_rdata;
  wire bus_we, bus_re;

  fpga_axil axil (
      .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
      .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot), .s_axi_awvalid(s_axi_awvalid),
      .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
      .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
      .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
      .s_axi_arprot(s_axi_arprot), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
      .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
      .s_axi_rready(s_axi_rready),
      .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re), .bus_rdata(bus_rdata)
  );

  fpga_bench bench (
      .clk(s_axi_aclk), .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we),
      .bus_re(bus_re), .bus_rdata(bus_rdata), .uo_out(uo_out), .uio67_out(uio67_out),
      .uio67_oe(uio67_oe), .uio67_in(uio67_in), .ui_ext(ui_ext), .heartbeat(heartbeat)
  );
endmodule
