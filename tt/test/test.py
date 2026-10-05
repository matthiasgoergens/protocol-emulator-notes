# SPDX-License-Identifier: Apache-2.0
# Structure from TinyTapeout/ttihp-verilog-template test/test.py (Apache-2.0).
#
# Runs unchanged on the RTL (make) and on a gate-level netlist (make GATES=yes): it touches only
# the tt_um_seqv2 ports, never internal signals.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# ISA v2 encodings, from prototypes/sequencer-v2/isa2.ml: word = (op << 12) | fields.
def setp(mask, val, oe, q):
    return (1 << 12) | (mask << 4) | (val << 3) | (oe << 2) | q


def jmp(addr):
    return (9 << 12) | addr


LOAD_DATA, LOAD_STROBE, RUN = 1, 2, 4


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def load(dut, words):
    """Shift words into the programme store (MSB first), then leave the loader idle."""
    for w in words:
        for i in range(15, -1, -1):
            dut.uio_in.value = LOAD_STROBE | (((w >> i) & 1) * LOAD_DATA)
            await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 1)


def pins(dut):
    return int(dut.uo_out.value)  # raises if any bit is X or Z: that is deliberate


@cocotb.test()
async def test_idle_until_run(dut):
    """With run low the sequencer is held in clear and drives no pin, even with a programme loaded."""
    await reset(dut)
    await load(dut, [setp(0xFF, 1, 1, 0), jmp(1)])
    await ClockCycles(dut.clk, 40)
    assert pins(dut) == 0, f"pins moved while run was low: {pins(dut):#04x}"


@cocotb.test()
async def test_setp_drives_pins(dut):
    """SETP mask=0x05 val=1: pins 0 and 2 go high and stay, the others stay low."""
    await reset(dut)
    await load(dut, [setp(0x05, 1, 1, 0), jmp(1)])
    dut.uio_in.value = RUN
    await ClockCycles(dut.clk, 40)
    assert pins(dut) == 0x05, f"expected 0x05, got {pins(dut):#04x}"
    # and a second programme, written over the first, after another reset
    await reset(dut)
    await load(dut, [setp(0xF0, 1, 1, 0), jmp(1)])
    dut.uio_in.value = RUN
    await ClockCycles(dut.clk, 40)
    assert pins(dut) == 0xF0, f"expected 0xF0, got {pins(dut):#04x}"
