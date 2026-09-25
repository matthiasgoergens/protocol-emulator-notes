// Verilator harness for emu_core: the ULX3S board, simulated.
//
// The host link is this process's stdin (bytes to the FPGA) and stdout (bytes from it), bit-banged
// as 8N1 at CLKS_PER_BIT clocks per bit on uart_rx / uart_tx, so the runner talks to the same UART
// and command engine the board has. Board models (header pull-ups, jumpers, the configuration
// flash, the RTC on the I2C bus, an acknowledging I2C slave on the header) are ports of
// ocaml/env.ml, statement for statement: a simulated run must match the OCaml prediction exactly.
//
// Options: --clks-per-bit N (must match the -G value it was built with), --jumper-0-7,
//          --header-i2c-slave, --header-i2c-addr HEX, --header-flash, --jumper-stream,
//          --flash-id HEX6, --rtc-addr HEX, --max-cycles N, --vcd FILE
#include "Vemu_core.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <poll.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

static inline int bit(unsigned v, int i) { return (v >> i) & 1; }

// ---------------------------------------------------------------- env.ml: i2c_slave
struct Slave {
  int addr;  // -1: acknowledge everything
  bool started = false; int nbits = 0; int cur = 0; bool first = false;
  bool addressed = false; bool pull = false; int p_sda = 1, p_scl = 1;
  explicit Slave(int a) : addr(a) {}
  void update(int sda, int scl) {
    if (p_scl == 1 && scl == 1 && p_sda == 1 && sda == 0) {
      started = true; nbits = 0; cur = 0; first = true; addressed = false;
    } else if (p_scl == 1 && scl == 1 && p_sda == 0 && sda == 1 && !pull) {
      started = false; addressed = false;
    } else if (started && p_scl == 0 && scl == 1) {
      if (nbits < 8) cur = ((cur << 1) | sda) & 0xFF;
      nbits++;
    } else if (started && p_scl == 1 && scl == 0) {
      if (nbits == 8) {
        if (first) { addressed = (addr < 0) ? true : ((cur >> 1) == addr); first = false; }
        pull = addressed;
      } else if (nbits == 9) {
        pull = false; nbits = 0; cur = 0;
      }
    }
    p_sda = sda; p_scl = scl;
  }
};

// ---------------------------------------------------------------- env.ml: flash
struct Flash {
  std::vector<int> id;
  int p_sclk = 0, p_csn = 1, nbits = 0, cmd = 0, nout = 0, miso = 1;
  std::vector<int> commands;
  void update(int sclk, int mosi, int csn) {
    if (csn == 1) { nbits = 0; nout = 0; miso = 1; }
    else {
      if (p_csn == 1) { nbits = 0; cmd = 0; nout = 0; }
      if (p_sclk == 0 && sclk == 1 && nbits < 8) {
        cmd = ((cmd << 1) | mosi) & 0xFF;
        nbits++;
        if (nbits == 8) commands.push_back(cmd);
      } else if (p_sclk == 1 && sclk == 0 && nbits == 8) {
        int n = (int)id.size();
        miso = (cmd == 0x9F && nout < 8 * n) ? ((id[nout / 8] >> (7 - (nout % 8))) & 1) : 1;
        nout++;
      }
    }
    p_sclk = sclk; p_csn = csn;
  }
};

int main(int argc, char** argv) {
  int cpb = 8; bool jumper07 = false, hslave = false, jstream = false; int rtc_addr = 0x6F;
  int hslave_addr = -1; bool hflash_on = false;
  long long max_cycles = 2000000000LL;
  const char* vcd = nullptr;
  Flash flash; flash.id = {0xEF, 0x40, 0x18};
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--clks-per-bit" && i + 1 < argc) cpb = atoi(argv[++i]);
    else if (a == "--jumper-0-7") jumper07 = true;
    else if (a == "--header-i2c-slave") hslave = true;
    else if (a == "--jumper-stream") jstream = true;
    else if (a == "--max-cycles" && i + 1 < argc) max_cycles = atoll(argv[++i]);
    else if (a == "--vcd" && i + 1 < argc) vcd = argv[++i];
    else if (a == "--rtc-addr" && i + 1 < argc) rtc_addr = (int)strtoul(argv[++i], nullptr, 16);
    else if (a == "--header-i2c-addr" && i + 1 < argc) hslave_addr = (int)strtoul(argv[++i], nullptr, 16);
    else if (a == "--header-flash") hflash_on = true;
    else if (a == "--flash-id" && i + 1 < argc) {
      unsigned v = strtoul(argv[++i], nullptr, 16);
      flash.id = {(int)((v >> 16) & 0xFF), (int)((v >> 8) & 0xFF), (int)(v & 0xFF)};
    } else { fprintf(stderr, "sim: unknown option %s\n", a.c_str()); return 2; }
  }
  const char* vargs[] = {"sim"};
  Verilated::commandArgs(1, vargs);
  Vemu_core* top = new Vemu_core;
  VerilatedVcdC* tfp = nullptr;
  if (vcd) { Verilated::traceEverOn(true); tfp = new VerilatedVcdC; top->trace(tfp, 99); tfp->open(vcd); }

  Slave hdr(hslave_addr), rtc(rtc_addr);
  Flash hflash; hflash.id = {0xEF, 0x40, 0x17};
  std::deque<unsigned char> inq;
  // host -> fpga serialiser
  int tx_bit = -1, tx_cnt = 0; unsigned tx_frame = 0;
  // fpga -> host deserialiser
  int rx_state = 0, rx_cnt = 0, rx_bit = 0; unsigned rx_sh = 0;
  long long line_idle = 0;
  bool stdin_open = true;

  top->clk = 0; top->rst = 1; top->uart_rx = 1;
  top->seq_pad_in = 0xFF; top->aux_spi_miso = 1; top->aux_sda_in = 1; top->aux_scl_in = 1;
  top->smp_pad_in = 0xF; top->board_status = 0;
  for (int i = 0; i < 8; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
  top->rst = 0;

  for (long long cyc = 0; cyc < max_cycles; cyc++) {
    top->clk = 0; top->eval();
    if (tfp) tfp->dump((uint64_t)(2 * cyc));
    // ---------------- board model: env.ml's step, from the outputs visible in this cycle
    unsigned ctrl = top->ctrl;
    unsigned out = top->seq_pad_out, oe = top->seq_pad_oe;   // oe already masks routed pins
    int pad[8];
    for (int i = 0; i < 8; i++) pad[i] = bit(oe, i) ? bit(out, i) : 1;
    if (hslave) {
      int scl = bit(oe, 5) ? bit(out, 5) : 1;
      int sda = (bit(oe, 4) && bit(out, 4) == 0) ? 0 : hdr.pull ? 0 : bit(oe, 4) ? bit(out, 4) : 1;
      hdr.update(sda, scl);
      pad[4] = sda; pad[5] = scl;
    }
    if (hflash_on) {
      hflash.update(pad[1], pad[2], pad[3]);
      if (!bit(oe, 6)) pad[6] = hflash.miso;
    }
    if (jumper07 && !bit(oe, 7)) pad[7] = pad[0];
    unsigned padv = 0;
    for (int i = 0; i < 8; i++) padv |= (unsigned)pad[i] << i;
    top->seq_pad_in = padv;
    if (ctrl & 0x01) {
      flash.update(top->aux_spi_sclk, top->aux_spi_mosi, top->aux_spi_csn);
      top->aux_spi_miso = flash.miso;
    } else top->aux_spi_miso = 1;
    if (ctrl & 0x02) {
      int scl = top->aux_scl_low ? 0 : 1;
      int sda = (top->aux_sda_low || rtc.pull) ? 0 : 1;
      rtc.update(sda, scl);
      top->aux_sda_in = sda; top->aux_scl_in = scl;
    } else { top->aux_sda_in = 1; top->aux_scl_in = 1; }
    unsigned sl = (top->str_pad_oe & top->str_pad_out) | (~top->str_pad_oe & 0xF);
    top->smp_pad_in = jstream ? sl : 0xF;

    // ---------------- host link: stdin -> uart_rx
    if ((cyc & 63) == 0 && stdin_open) {
      bool block = inq.empty() && tx_bit < 0 && rx_state == 0 && line_idle > 12LL * cpb && !top->running_o;
      struct pollfd p = {0, POLLIN, 0};
      int r = poll(&p, 1, block ? 5000 : 0);
      if (r > 0 && (p.revents & (POLLIN | POLLHUP))) {
        unsigned char buf[4096];
        ssize_t n = read(0, buf, sizeof buf);
        if (n <= 0) stdin_open = false;
        else for (ssize_t i = 0; i < n; i++) inq.push_back(buf[i]);
      }
    }
    if (!stdin_open && inq.empty() && tx_bit < 0 && rx_state == 0 && line_idle > 12LL * cpb && !top->running_o) break;
    if (tx_bit < 0 && !inq.empty()) {
      tx_frame = (1u << 9) | ((unsigned)inq.front() << 1); inq.pop_front(); tx_bit = 0; tx_cnt = cpb;
    }
    if (tx_bit >= 0) {
      top->uart_rx = (tx_frame >> tx_bit) & 1;
      if (--tx_cnt == 0) { tx_cnt = cpb; if (++tx_bit == 10) tx_bit = -1; }
    } else top->uart_rx = 1;

    top->clk = 1; top->eval();
    if (tfp) tfp->dump((uint64_t)(2 * cyc + 1));

    // ---------------- host link: uart_tx -> stdout
    int line = top->uart_tx;
    line_idle = line ? line_idle + 1 : 0;
    if (rx_state == 0) {
      if (!line) { rx_state = 1; rx_cnt = cpb / 2; rx_bit = 0; rx_sh = 0; }
    } else if (--rx_cnt == 0) {
      rx_cnt = cpb;
      if (rx_bit == 0) { if (line) rx_state = 0; }
      else if (rx_bit <= 8) rx_sh |= (unsigned)line << (rx_bit - 1);
      else {
        rx_state = 0;
        if (line) { unsigned char b = rx_sh & 0xFF; if (write(1, &b, 1) != 1) break; }
        else fprintf(stderr, "sim: framing error on uart_tx\n");
      }
      rx_bit++;
    }
  }
  if (!flash.commands.empty()) {
    fprintf(stderr, "sim: flash commands:");
    for (int c : flash.commands) fprintf(stderr, " %02x", c);
    fprintf(stderr, "\n");
  }
  if (tfp) tfp->close();
  top->final();
  delete top;
  return 0;
}
