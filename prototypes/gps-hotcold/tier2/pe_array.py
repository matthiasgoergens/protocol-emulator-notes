"""The GPS correlator as a configuration of the generic PE row, bit-exact.

pe16 (../pe-synth/pe_rtl.ml): s <= alu(op, x, y), x = state or neighbour, y = k or state, ALU
add/sub (saturating)/max/min, output = state or the pipeline register (the neighbour input, one
clock late). Configuration is static.

Proposed extension ("tag lane", one bit beside the 16-bit neighbour word):
  tag_in  from the left neighbour's tag_out, or from a row-wide broadcast line   (1 config bit)
  tag use none | negate the neighbour operand x | carry-in                        (2 config bits)
  wrap    wrapping add instead of saturating (phase accumulators)                 (1 config bit)
  tag_out tag_in passed on (registered) | state MSB | carry out                   (2 config bits)
Nothing else changes: the op stays static; data-dependent sign comes only through the tag.

Row configuration for GPS (one row per quadrature arm, I and Q):
  PE 0  carrier NCO     x = state, y = k (tuning word), add, wrap; tag_out = MSB;
                        output = pipe, so the sample word passes on to PE 1
                        (the Q row's NCO starts a quarter turn ahead: its MSB is the sine sign)
  PE 1  mixer           x = neighbour (the sample as +-1), y = k = 0, add, tag negates x;
                        tag_in = PE 0's MSB; output = state: the carrier-wiped sample
  PE 2.. correlators    x = neighbour, y = state, add, tag negates x; tag_in = broadcast code
                        chip; output = pipe, so the wiped sample walks one PE per clock:
                        PE 2+j integrates wiped(n - j) * code(n), i.e. code offset -j
The code comes from a code NCO PE (k = 20480 = 5/16 chip per sample, wrap, tag_out = carry)
stepping a G1/G2 LFSR assist; the broadcast line carries its output.

This module simulates that row clock by clock (pe_row_pass) and checks it against the
vectorised correlation that acq.py uses for the Monte Carlo (reference_pass).
"""
import numpy as np

W = 16
MASK = (1 << W) - 1


def sat16(v):
    return max(-(1 << 15), min((1 << 15) - 1, v))


class PE:
    def __init__(self, x_state, y_k, k=0, op="add", wrap=False, out_state=False,
                 tag_src="left", tag_use="none", tag_out="pass"):
        self.x_state, self.y_k, self.k, self.op, self.wrap = x_state, y_k, k, op, wrap
        self.out_state, self.tag_src, self.tag_use, self.tag_out_sel = out_state, tag_src, tag_use, tag_out
        self.s = 0          # state (signed for saturating use, unsigned 16-bit for wrap)
        self.pipe = 0
        self.tag_reg = 0

    def outputs(self):
        out = self.s if self.out_state else self.pipe
        if self.tag_out_sel == "msb":
            t = (self.s >> 15) & 1
        else:
            t = self.tag_reg
        return out, t

    def clock(self, nbr, tag_in):
        x = self.s if self.x_state else nbr
        y = self.k if self.y_k else self.s
        if self.tag_use == "negate" and tag_in:
            x = -x
        if self.op == "add":
            r = x + y
        else:
            r = x - y
        self.s = (r & MASK) if self.wrap else sat16(r)
        self.pipe = nbr
        self.tag_reg = tag_in


def pe_row_pass(samples, carrier_k, carrier_phase0, quarter, code_bits, K):
    """One row, one replay pass. samples: +-1 per clock (then zeros to flush), code_bits: 0/1
    per clock on the broadcast line (1 = negate). Returns the K correlator states."""
    nco = PE(x_state=True, y_k=True, k=carrier_k, wrap=True, tag_out="msb")
    nco.s = (carrier_phase0 + quarter) & MASK
    mix = PE(x_state=False, y_k=True, k=0, out_state=True, tag_use="negate", tag_src="left")
    cor = [PE(x_state=False, y_k=False, tag_use="negate", tag_src="broadcast") for _ in range(K)]
    n = len(samples)
    for t in range(n + K + 3):
        x_in = int(samples[t]) if t < n else 0
        b = int(code_bits[t]) if t < len(code_bits) else 0
        # combinational outputs of this clock (registered values)
        o_nco, t_nco = nco.outputs()
        o_mix, _ = mix.outputs()
        outs = [c.outputs()[0] for c in cor]
        nco.clock(x_in, 0)
        mix.clock(o_nco, t_nco)
        prev = o_mix
        for j, c in enumerate(cor):
            c.clock(prev, b)
            prev = outs[j]
    return [c.s for c in cor]


def carrier_sign(phase0, k, n, quarter):
    """+-1 carrier signs as the NCO's MSB gives them: -1 where the MSB is set"""
    ph = (phase0 + quarter + k * np.arange(n, dtype=np.int64)) & MASK
    return 1 - 2 * (ph >> 15)


def reference_pass(samples, carrier_k, carrier_phase0, quarter, code_pm, K, lag):
    """closed form of the same pass: the mixer sees sample n with the NCO phase after n
    updates; correlator j sees wiped(n) against code at clock n + lag + j"""
    n = len(samples)
    cs = carrier_sign(carrier_phase0, carrier_k, n, quarter)
    wiped = np.asarray(samples, np.int64) * cs
    return [int(np.sum(wiped * code_pm[lag + j: lag + j + n])) for j in range(K)]
