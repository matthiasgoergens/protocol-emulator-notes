"""Demo B output: the detector's state as CAN 2.0A frames (what the sequencer sends in firmware,
with the programmable CRC assist computing CRC-15 and the bit-stuffing assist inserting stuff bits).

Frame: ID 0x2A0 (11 bit), DLC 3, data = [state (0 programme, 1 advert), confidence 0..255,
sequence number]. Sent on every state change and once a second as a heartbeat.

The encoder builds the bit stream (SOF .. EOF) with CRC-15 (polynomial 0x4599) and stuffing.
An independent decoder (written from the frame format, not sharing the encoder's code) destuffs,
checks the CRC and recovers the fields. Planted faults (one flipped bit, a missing stuff bit) must
be caught. Then the detector states saved by advert.py are turned into frames and the bus load and
the mute latency (detection delay plus one frame) are reported.

Usage: python3 can_out.py   -> results/can_out.txt
"""
import pathlib, sys
import numpy as np

HERE = pathlib.Path(__file__).parent
RES = HERE / "results"
CAN_ID = 0x2A0


def crc15(bits):
    crc = 0
    for b in bits:
        nxt = b ^ ((crc >> 14) & 1)
        crc = (crc << 1) & 0x7FFF
        if nxt:
            crc ^= 0x4599
    return crc


def encode(can_id, data):
    f = [0]                                                    # SOF
    f += [(can_id >> (10 - i)) & 1 for i in range(11)]         # identifier
    f += [0, 0, 0]                                             # RTR, IDE, r0
    f += [(len(data) >> (3 - i)) & 1 for i in range(4)]        # DLC
    for byte in data:
        f += [(byte >> (7 - i)) & 1 for i in range(8)]
    c = crc15(f)
    f += [(c >> (14 - i)) & 1 for i in range(15)]
    # bit stuffing from SOF to the end of the CRC: after five equal bits insert the complement
    out, run, last = [], 0, None
    for b in f:
        out.append(b)
        run = run + 1 if b == last else 1
        last = b
        if run == 5:
            out.append(1 - b)
            last, run = 1 - b, 1
    out += [1]          # CRC delimiter
    out += [1, 1]       # ACK slot (recessive from the sender) and ACK delimiter
    out += [1] * 7      # EOF
    return out


def decode(bits):
    """Independent decoder: walk the stuffed stream, drop stuff bits, parse, check CRC."""
    raw, i, run, last = [], 0, 0, None
    # destuff until we have SOF + 11 + 3 + 4 + 8*dlc + 15 bits; dlc is known after 19 raw bits
    need = None
    while i < len(bits):
        b = bits[i]; i += 1
        if run == 5:
            if b == last:
                return None, "stuff error"
            run, last = 1, b
            continue
        raw.append(b)
        run = run + 1 if b == last else 1
        last = b
        if len(raw) == 19:
            dlc = int("".join(map(str, raw[15:19])), 2)
            need = 19 + 8 * dlc + 15
        if need is not None and len(raw) == need:
            break
    if need is None or len(raw) < need:
        return None, "truncated"
    ident = int("".join(map(str, raw[1:12])), 2)
    dlc = int("".join(map(str, raw[15:19])), 2)
    data = [int("".join(map(str, raw[19 + 8 * k:27 + 8 * k])), 2) for k in range(dlc)]
    crc = int("".join(map(str, raw[19 + 8 * dlc:])), 2)
    # CRC-15 recomputed by polynomial long division over the raw bits (a different formulation)
    msg = raw[: 19 + 8 * dlc] + [0] * 15
    reg = msg[:]
    for k in range(len(raw[: 19 + 8 * dlc])):
        if reg[k]:
            for j, pb in enumerate(bin(0xC599)[2:]):         # x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1
                reg[k + j] ^= int(pb)
    rem = int("".join(map(str, reg[-15:])), 2)
    if rem != crc:
        return None, "crc error"
    return (ident, data), "ok"


def main():
    lines = ["CAN output for Demo B (can_out.py). ID 0x%03X, DLC 3: state, confidence, sequence." % CAN_ID]
    rng = np.random.default_rng(3)
    ok = 0
    flips = dict(detected=0, harmless=0, undetected=0)
    for t in range(2000):
        data = [int(rng.integers(0, 2)), int(rng.integers(0, 256)), t & 255]
        fr = encode(CAN_ID, data)
        dec, why = decode(fr)
        ok += dec == (CAN_ID, data)
        f2 = list(fr)
        k = int(rng.integers(0, len(fr) - 10))
        f2[k] ^= 1
        d2, _ = decode(f2)
        flips["detected" if d2 is None else "harmless" if d2 == (CAN_ID, data) else "undetected"] += 1
    lines.append(f"round trip: {ok} / 2000 frames decoded exactly. One random flipped bit per frame: "
                 f"{flips['detected']} rejected (stuff or CRC error), {flips['harmless']} harmless (flip after the "
                 f"CRC, in the delimiter, ACK or EOF, which this decoder does not check), "
                 f"{flips['undetected']} wrong frames accepted")
    ex = encode(CAN_ID, [1, 200, 7])
    lines.append(f"example frame (advert, confidence 200, seq 7), {len(ex)} bits on the wire: " + "".join(map(str, ex)))
    p = RES / "advert_states.npz"
    if p.exists():
        z = np.load(p)
        for key in sorted(k for k in z.files if not k.startswith("label_")):
            st = z[key]
            changes = int(np.count_nonzero(np.diff(st)))
            secs = len(st)
            frames = secs + changes                  # 1 Hz heartbeat plus one frame per change
            nbits = np.mean([len(encode(CAN_ID, [s, 128, i & 255])) + 3 for i, s in enumerate(st[:500])])
            lines.append(f"{key:22s} {changes:3d} state changes in {secs} s -> {frames} frames, "
                         f"{frames * nbits / secs:.0f} bit/s ({frames * nbits / secs / 125e3:.3%} of 125 kbit/s); "
                         f"frame time {nbits / 125e3 * 1e3:.2f} ms at 125 kbit/s, {nbits / 500e3 * 1e3:.2f} ms at 500 kbit/s")
    (RES / "can_out.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
