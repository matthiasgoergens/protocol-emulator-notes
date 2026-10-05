// Our UART transmitter (the compiler's UART programme on the v2 core, thread 0, pin 0) and Jane
// Street's Uart.Tx (github.com/janestreet/hardcaml_hobby_boards, MIT; built unmodified by
// build_hobby_tx.sh), side by side, sending the same N_BYTES bytes (README.md, section 7).
//
// Our core takes byte i when its IN executes (the host is always ready). Jane Street's Tx takes
// byte i when it is in its Start state with data_in_valid high. Two ways to offer it the bytes:
//   LOCKED = 1: byte i becomes valid for the Tx on the clock after our core has taken it, so both
//               transmitters start each frame from the same event;
//   LOCKED = 0: every byte is valid for the Tx as soon as it can take it, as for our core.
// line_ours is pin 0 as the wire sees it (the driven level, or 1 when released: pulled up).
module uart_pair #(parameter LOCKED = 1, parameter N_BYTES = 2) (
    input clock,
    input clear,
    input [8 * N_BYTES - 1:0] bytes,   // byte i at bits 8i+7..8i, for our core
    input [8 * N_BYTES - 1:0] bytes_js,  // the same for the Tx (equal to bytes, except in a control)
    output line_ours,
    output txd_js,
    output [3:0] taken_ours,           // bytes taken so far
    output [3:0] taken_js
);
  wire [9:0] imem_addr;
  reg [15:0] imem_data;
  wire [15:0] rom_word;
  uart_rom rom (.addr(imem_addr), .data(rom_word));
  always @(posedge clock) imem_data <= rom_word;    // the store's one-clock synchronous read

  reg [3:0] n_ours, n_js;
  wire [7:0] byte_ours = n_ours < N_BYTES ? bytes[8 * n_ours +: 8] : 8'h00;
  wire [7:0] byte_js = n_js < N_BYTES ? bytes_js[8 * n_js +: 8] : 8'h00;
  wire host_in_ready;
  wire [7:0] pin_out, pin_oe;
  deadline_sequencer_v2 core (
    .flags(16'd0), .port_out_ready(4'd0), .bank_rdata(8'd0), .pin_in4(32'hffffffff), .pin_in(8'hff),
    .host_in(byte_ours), .host_in_valid(n_ours < N_BYTES),
    .port_in3(8'd0), .port_in2(8'd0), .port_in1(8'd0), .port_in0(8'd0), .port_in_valid(4'd0),
    .boot_pc(32'd0), .ctl_pc(8'd0), .imem_data(imem_data), .boot_page(8'b11_10_01_00), .ctl_page(2'd0),
    .clear(clear), .clock(clock), .ctl_thread(2'd0), .ctl_valid(1'b0),
    .imem_addr(imem_addr), .pin_out(pin_out), .pin_oe(pin_oe), .host_in_ready(host_in_ready));
  assign line_ours = pin_oe[0] ? pin_out[0] : 1'b1;

  wire js_ready;
  wire js_valid = LOCKED ? n_js < n_ours : n_js < N_BYTES;
  hobby_uart_tx js (.clock(clock), .clear(clear), .data_in(byte_js), .data_in_valid(js_valid),
                    .txd(txd_js), .data_in_ready(js_ready));
  // the Tx's data_in_ready is high exactly in its Start state, where a valid byte is taken
  wire js_takes = js_valid && js_ready;

  always @(posedge clock)
    if (clear) begin n_ours <= 4'd0; n_js <= 4'd0; end
    else begin
      if (host_in_ready) n_ours <= n_ours + 4'd1;
      if (js_takes) n_js <= n_js + 4'd1;
    end
  assign taken_ours = n_ours;
  assign taken_js = n_js;
endmodule
