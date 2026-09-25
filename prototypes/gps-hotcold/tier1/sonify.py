"""Hot/cold sonification: NMEA bytes -> integer navigation -> sound parameters -> the chip's audio
path, rendered to WAV, plus a plot.

Controller (host, integer, once per fix):
  distance -> beep period   85 ms * sqrt(d / 1 m), from a 44-entry ROM indexed by half-octaves
                            of the distance (3 m: 150 ms, 10 m: 270 ms, 50 m: 600 ms, 500 m: 1.9 s);
                            under 6 m a continuous warble ("found"; GPS error is 2-5 m)
  trend    -> beep shape    warmer: two notes up (880 -> 1320 Hz); colder: two notes down
                            (440 -> 330 Hz); neutral: one 660 Hz note. Trend = change of the
                            smoothed distance over 5 s, +-2.5 m to enter, +-1 m to leave (hysteresis)
  direction -> stereo       target bearing minus course over ground, 16 sectors, constant-power
                            pan; behind you both ears quiet; no cue under 0.4 m/s (course is noise)
  no fix   -> a soft tick every 3 s

Audio path (generic blocks, per ear; see README "Tier 1 mapping"):
  NCO PE     16-bit wrapping accumulator, enabled every 256th clock (255.75 kHz); its MSB is a
             square wave at k * 255750 / 65536 Hz (3.9 Hz steps)
  sigma-delta PE  16-bit wrapping accumulator, enabled every 16th clock (4.092 MHz), adding the
             amplitude word A'; its carry is a 1-bit stream of density A' / 65536
  pin        XOR of the two: density 1 - A' while the square is high, A' while low, so a square
             wave of amplitude 1 - 2A' (A' = 1/2 is silence). Host rewrites k and A' every 1 ms
             (5 ms attack and release ramps).
  RC         two cascaded first-order RC sections at 6 kHz, then the speaker. The renderer
             models the pin at 4.092 MHz, the RC, and averages down to 22 kHz for the WAV.
Usage: sonify.py RESULTS_DIR [WAV_DIR]
"""
import json, math, sys, wave
import numpy as np
from numba import njit
import navfix as nf

F_CLK = 65_472_000
F_SD = F_CLK // 16            # 4.092 MHz sigma-delta enable
F_NCO = F_CLK // 256          # 255.75 kHz NCO enable
DEC = 186                     # 4.092 MHz / 186 = 22 kHz WAV
F_WAV = F_SD // DEC
TICK = F_SD // 1000           # sigma-delta samples per 1 ms control tick (4092)

PERIOD_ROM = [max(120, min(2400, round(85 * math.sqrt(2 ** (i / 2) / 100)))) for i in range(48)]


def kword(f):
    return round(f * 65536 / F_NCO)


def pan_gains(rel_ba, moving):
    """16-sector constant-power pan (Q15 gains for left, right) from the relative bearing"""
    if not moving:
        return 23170, 23170                      # centre, 1/sqrt(2)
    sec = ((rel_ba + (1 << 27)) >> 28) & 15      # 16 sectors, sector 0 = straight ahead
    ang = (sec if sec < 8 else sec - 16) * 22.5
    if abs(ang) > 112.5:                         # behind: both ears quiet
        return 9000, 9000
    th = (ang + 90) / 180 * math.pi / 2          # -90 deg -> all left, +90 -> all right
    return round(32767 * math.cos(th)), round(32767 * math.sin(th))


def controller(fixes, tgt):
    """-> per-fix list of dicts (the plan for the following second)"""
    plans = []
    hist = []
    s = None
    trend = 0
    for fx in fixes:
        hh, mm, ss = int(fx["time"][0:2]), int(fx["time"][2:4]), int(fx["time"][4:6])
        sec = hh * 3600 + mm * 60 + ss
        if not fx["valid"]:
            plans.append(dict(mode="nofix", sec=sec)); hist.clear(); s = None; continue
        d, bba, far = nf.distance_bearing(tgt, fx["lat"], fx["lon"])
        s = d << 4 if s is None else s + ((d << 4) - s >> 2)     # EMA, alpha 1/4, 4 fraction bits
        hist.append(s)
        if len(hist) > 6: hist.pop(0)
        closing = (hist[0] - hist[-1]) >> 4 if len(hist) == 6 else 0
        if trend == 0:
            trend = 1 if closing >= 250 else -1 if closing <= -250 else 0
        elif trend == 1 and closing < 100:
            trend = 0 if closing > -250 else -1
        elif trend == -1 and closing > -100:
            trend = 0 if closing < 250 else 1
        moving = (fx["speed_ckn"] or 0) >= 78                      # 0.4 m/s
        rel = (bba - nf.cdeg_to_ba(fx["cog_cdeg"] or 0)) % nf.TURN
        gl, gr = pan_gains(rel, moving)
        idx = min(47, 2 * max(0, d.bit_length() - 1) + ((d >> max(0, d.bit_length() - 2)) & 1)) if d > 0 else 0
        plans.append(dict(mode="found" if d < 600 else "beep", d_cm=d, bearing=bba, rel=rel,
                          trend=trend, closing=closing, period_ms=PERIOD_ROM[idx], gl=gl, gr=gr,
                          moving=moving, far=far, sec=sec))
    # one plan per second: a second whose RMC was lost (bad checksum) keeps the previous plan
    t0 = plans[0]["sec"]
    full = []
    for p in plans:
        while len(full) < p["sec"] - t0:
            full.append(dict(full[-1], held=True))
        full.append(p)
    return full


def schedule(plans):
    """1 ms control ticks: (kL, kR, aL, aR) with a in Q15 amplitude 0..32767. The beep phase runs
    continuously across fixes so a new period takes effect at the next beep."""
    n = len(plans) * 1000
    k = np.zeros((n, 2), np.int64)
    amp = np.zeros((n, 2), np.int64)
    next_beep = 0
    for i, p in enumerate(plans):
        for ms in range(1000):
            t = i * 1000 + ms
            if p["mode"] == "nofix":
                if t % 3000 < 15:
                    k[t] = kword(1000); amp[t] = 6000
                continue
            if p["mode"] == "found":
                f = 1320 if (t // 62) % 2 else 1760
                k[t] = kword(f)
                amp[t] = (p["gl"], p["gr"]) if p["moving"] else (23170, 23170)
                next_beep = t
                continue
            if t >= next_beep:
                start = next_beep
                next_beep = start + p["period_ms"]
            else:
                start = next_beep - p["period_ms"]
            pos = t - start
            blen = min(90, p["period_ms"] * 2 // 5)
            if 0 <= pos < blen:
                half = pos < blen // 2
                if p["trend"] > 0:
                    f = 880 if half else 1320
                elif p["trend"] < 0:
                    f = 440 if half else 330
                else:
                    f = 660
                k[t] = kword(f)
                amp[t] = (p["gl"], p["gr"])
    # 5 ms attack/release: slew-limit the amplitude
    step = 32767 // 5
    out = np.zeros_like(amp)
    cur = np.zeros(2, np.int64)
    for t in range(n):
        cur = np.clip(amp[t], cur - step, cur + step)
        out[t] = cur
    return k, out


@njit(cache=True)
def render(k, amp, rc_alpha):
    """pin model at 4.092 MHz for both ears, two RC poles, boxcar-average down to 22 kHz"""
    n_ms = k.shape[0]
    n_out = n_ms * TICK // DEC
    out = np.zeros((n_out, 2), np.float32)
    for ch in range(2):
        nco = 0
        sd = 0
        y1 = 0.0
        y2 = 0.0
        acc = 0.0
        cnt = 0
        o = 0
        for t in range(n_ms):
            a = amp[t, ch]
            aq = (32768 - a)                       # A' = (1 - a) / 2 in 16 bits: 65536 * (1 - a/32768) / 2
            kk = k[t, ch]
            for j in range(TICK):
                if j % 16 == 0:
                    nco = (nco + kk) & 0xFFFF
                sq = nco >> 15
                sd += aq
                pdm = sd >> 16
                sd &= 0xFFFF
                pin = sq ^ pdm
                x = 1.0 if pin else -1.0
                y1 += rc_alpha * (x - y1)
                y2 += rc_alpha * (y1 - y2)
                acc += y2
                cnt += 1
                if cnt == DEC:
                    if o < n_out:
                        out[o, ch] = acc / DEC
                    o += 1
                    acc = 0.0
                    cnt = 0
    return out


def write_wav(path, x):
    pcm = np.clip(x * 0.9 * 32767, -32767, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(F_WAV); w.writeframes(pcm.tobytes())


def main(rdir, wdir=None):
    wdir = wdir or rdir
    meta = json.load(open(f"{rdir}/walk.json"))
    tgt = nf.set_target(*meta["target"])
    fixes, stats = nf.parse(open(f"{rdir}/nmea.txt", "rb").read())
    plans = controller(fixes, tgt)
    k, amp = schedule(plans)
    rc_alpha = 1 - math.exp(-2 * math.pi * 6000 / F_SD)
    audio = render(k, amp, rc_alpha)
    write_wav(f"{wdir}/hotcold_full.wav", audio)
    np.save(f"{wdir}/hotcold_audio.npy", audio)
    with open(f"{rdir}/plans.csv", "w") as f:
        f.write("fix,mode,d_cm,bearing_deg,rel_deg,trend,closing_cm_per_5s,period_ms,gain_l,gain_r,held\n")
        for i, p in enumerate(plans):
            if p["mode"] == "nofix":
                f.write(f"{i},nofix,,,,,,,,,\n"); continue
            f.write(f"{i},{p['mode']},{p['d_cm']},{p['bearing']/nf.TURN*360:.3f},{p['rel']/nf.TURN*360:.2f},"
                    f"{p['trend']},{p['closing']},{p['period_ms']},{p['gl']},{p['gr']},{int(p.get('held', False))}\n")
    print(f"fixes {len(fixes)}, audio {audio.shape[0] / F_WAV:.1f} s at {F_WAV} Hz; wav in {wdir}")


if __name__ == "__main__":
    main(*sys.argv[1:])
