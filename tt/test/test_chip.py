# SPDX-License-Identifier: Apache-2.0
# Structure from TinyTapeout/ttihp-verilog-template test/test.py (Apache-2.0).
#
# The combined chip (prototypes/chip-top) through Tiny Tapeout's ports only, so it runs unchanged
# on the RTL (make CHIP=yes) and on a gate-level netlist. The host link follows
# prototypes/chip-top/README.md ("Host link protocol"): uio[3:0] data, uio[4] strobe (every change
# moves a nibble, high nibble first), uio[5] read request.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

T_REG, T_PROG, OP_WRITE, OP_READ = 0, 1, 1, 2
R_CTRL, R_BOOT_PC0, R_BOOT_PAGE, R_STATUS = 0x00, 0x04, 0x08, 0x01


def setp(mask, val, oe, q=0):
    return (1 << 12) | (mask << 4) | (val << 3) | (oe << 2) | q


def jmp(addr):
    return (9 << 12) | addr


class Host:
    def __init__(self, dut):
        self.dut, self.s, self.r, self.d = dut, 0, 0, 0

    def drive(self, oe_data):
        v = (self.d & 0xF) if oe_data else 0
        self.dut.uio_in.value = v | (self.s << 4) | (self.r << 5)

    async def nibble(self, n):
        self.d = n
        self.drive(True)
        await ClockCycles(self.dut.clk, 2)
        self.s ^= 1
        self.drive(True)
        await ClockCycles(self.dut.clk, 2)

    async def byte(self, b):
        await self.nibble(b >> 4)
        await self.nibble(b & 0xF)

    async def write(self, tgt, addr, data):
        for b in [(OP_WRITE << 4) | tgt, addr >> 8, addr & 0xFF, len(data) - 1] + list(data):
            await self.byte(b)

    async def read(self, tgt, addr, n):
        for b in [(OP_READ << 4) | tgt, addr >> 8, addr & 0xFF, n - 1]:
            await self.byte(b)
        self.drive(False)                       # release D
        await ClockCycles(self.dut.clk, 8)
        self.r = 1
        self.drive(False)
        await ClockCycles(self.dut.clk, 8)
        out = []
        for _ in range(n):
            hi = int(self.dut.uio_out.value) & 0xF
            self.s ^= 1
            self.drive(False)
            await ClockCycles(self.dut.clk, 8)
            lo = int(self.dut.uio_out.value) & 0xF
            self.s ^= 1
            self.drive(False)
            await ClockCycles(self.dut.clk, 8)
            out.append((hi << 4) | lo)
        self.r = 0
        self.drive(False)
        await ClockCycles(self.dut.clk, 8)
        return out


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    return Host(dut)


@cocotb.test()
async def test_registers_read_back(dut):
    """Reset values and a written register read back through the link; uio_oe follows R."""
    h = await reset(dut)
    assert await h.read(T_REG, R_CTRL, 1) == [2], "control resets to 2 (stopped, assists held)"
    await h.write(T_REG, R_BOOT_PC0, [0x12, 0x34, 0x56, 0x78, 0x9B])
    assert await h.read(T_REG, R_BOOT_PC0, 5) == [0x12, 0x34, 0x56, 0x78, 0x9B]
    assert int(dut.uio_oe.value) & 0xF == 0, "the chip releases the data lines when R is low"


@cocotb.test()
async def test_programme_drives_pins(dut):
    """Load a two-word programme through the link, run it: SETP drives the pins it names."""
    h = await reset(dut)
    prog = [setp(0xA5, 1, 1), jmp(1)]
    data = []
    for w in prog:
        data += [w & 0xFF, w >> 8]
    await h.write(T_PROG, 0, data)
    assert await h.read(T_PROG, 0, 4) == data, "the store reads back while stopped"
    # threads 1-3 park on word 1 (JMP 1)
    await h.write(T_REG, R_BOOT_PC0, [0, 1, 1, 1, 0])
    await h.write(T_REG, R_CTRL, [3])          # run, assists held
    await ClockCycles(dut.clk, 40)
    await FallingEdge(dut.clk)
    assert int(dut.uo_out.value) == 0xA5, f"pins {int(dut.uo_out.value):#04x}"
    assert await h.read(T_REG, R_STATUS, 1) == [0], "no refused access, no overflow"
