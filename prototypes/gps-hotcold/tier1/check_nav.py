"""Checks for navfix.py.

1. Parser against pynmea2 (independent): every sentence of the walk's stream. For each checked
   RMC both must agree on validity, time, latitude, longitude (exactly, in 1e-5 arcminute units),
   speed and course; the corrupted sentence must be rejected by both.
2. Precision of the integer distance/bearing against geographiclib's WGS84 geodesic, at five
   latitudes and 1-500 m. "arith" compares against the geodesic between the NMEA-rounded
   coordinates (the arithmetic alone); "total" against the true coordinates (adds the NMEA
   rounding). Also for a 4-decimal module.
3. Negative controls: a parser with the checksum test disabled accepts the corrupted sentence;
   a navigator using the cosine of 0 degrees instead of the target's latitude fails the bound.
Usage: check_nav.py RESULTS_DIR
"""
import math, sys
import numpy as np
import pynmea2
from geographiclib.geodesic import Geodesic
import navfix as nf

G = Geodesic.WGS84


def check_parser(d):
    data = open(f"{d}/nmea.txt", "rb").read()
    fixes, stats = nf.parse(data)
    ref = []
    rejected = 0
    for line in data.decode().split("\r\n"):
        if not line:
            continue
        try:
            m = pynmea2.parse(line, check=True)
        except pynmea2.ChecksumError:
            rejected += 1
            continue
        if isinstance(m, pynmea2.types.talker.RMC):
            ref.append(m)
    assert len(ref) == len(fixes), (len(ref), len(fixes))
    bad = 0
    for ours, m in zip(fixes, ref):
        valid = m.status == "A"
        ok = ours["valid"] == valid and ours["time"] == m.data[0]
        if valid:
            # pynmea2's decimal-degree properties, converted back to units and rounded
            lat = round(m.latitude * nf.U_PER_DEG)
            lon = round(m.longitude * nf.U_PER_DEG)
            ok &= ours["lat"] == lat and ours["lon"] == lon
            # ours truncates to hundredths (speed has 3 decimals); compare with the truncated float
            ok &= ours["speed_ckn"] == math.floor(m.spd_over_grnd * 100 + 1e-6)
            ok &= ours["cog_cdeg"] == math.floor(m.true_course * 100 + 1e-6)
        bad += not ok
    lines = [f"parser vs pynmea2 {pynmea2.__version__}: {len(fixes)} RMC sentences compared, {bad} disagree",
             f"  our parser: {stats}",
             f"  pynmea2 checksum rejections: {rejected}; ours: {stats['bad_checksum']}"]
    # control: disable our checksum test -> the corrupted RMC gets through with a wrong latitude
    orig = nf.Parser.feed
    def feed_nocheck(self, b):
        if self.state == "cs" and len(self.cs_txt) == 1:
            self.cs_txt += chr(b); self.state = "idle"; self.stats["sentences"] += 1
            return self._sentence(self.buf.decode("ascii", "replace"))
        return orig(self, b)
    nf.Parser.feed = feed_nocheck
    fx2, _ = nf.parse(data)
    nf.Parser.feed = orig
    lines.append(f"  control, checksum test disabled: {len(fx2)} RMC accepted (vs {len(fixes)}); "
                 f"so the checksum is what rejects the corrupted one")
    return lines, bad == 0 and stats["bad_checksum"] == rejected == 1 and len(fx2) == len(fixes) + 1


def precision(frac_digits=5, broken=False, n=4000, seed=7):
    rng = np.random.default_rng(seed)
    out = []
    worst = 0
    for lat0 in (0.0, 1.3441, 30.0, 45.0, 60.0, 75.0):
        ea, ba, et, bt = [], [], [], []
        for _ in range(n):
            tlat = lat0 + rng.uniform(-0.01, 0.01)
            tlon = rng.uniform(-179, 179)
            dist = math.exp(rng.uniform(math.log(1.0), math.log(500.0)))
            az = rng.uniform(-180, 180)
            p = G.Direct(tlat, tlon, az, dist)
            q = 10 ** (5 - frac_digits)
            def rnd(v):
                return round(v * nf.U_PER_DEG / q) * q
            tgt = nf.set_target(tlat, tlon) if not broken else nf.set_target(0.0, tlon)
            tgt["lat"], tgt["lon"] = rnd(tlat), rnd(tlon)
            dcm, bba, far = nf.distance_bearing(tgt, rnd(p["lat2"]), rnd(p["lon2"]))
            d_m = dcm / 100
            b_deg = bba / nf.TURN * 360
            # geodesic from walker to target, between the rounded coordinates
            g = G.Inverse(rnd(p["lat2"]) / nf.U_PER_DEG, rnd(p["lon2"]) / nf.U_PER_DEG,
                          tgt["lat"] / nf.U_PER_DEG, tgt["lon"] / nf.U_PER_DEG)
            gt = G.Inverse(p["lat2"], p["lon2"], tlat, tlon)
            def angerr(a, b):
                return abs((a - b + 180) % 360 - 180)
            ea.append(abs(d_m - g["s12"])); et.append(abs(d_m - gt["s12"]))
            if g["s12"] > 5:     # bearing is meaningless at 1-2 m with 2 cm coordinates
                ba.append(angerr(b_deg, g["azi1"])); bt.append(angerr(b_deg, gt["azi1"]))
        ea, et, ba, bt = map(np.array, (ea, et, ba, bt))
        worst = max(worst, ea.max())
        out.append(f"  lat {lat0:6.2f}: distance err arith max {ea.max()*100:6.2f} cm p99 {np.percentile(ea,99)*100:6.2f} cm | "
                   f"total max {et.max()*100:6.2f} cm | bearing (>5 m) arith max {ba.max():.4f} deg, total max {bt.max():.3f} deg")
    return out, worst


def main(d):
    res = []
    lines, ok = check_parser(d)
    res += lines + [f"  PARSER {'PASS' if ok else 'FAIL'}", ""]
    for fd in (5, 4):
        o, w = precision(frac_digits=fd)
        res += [f"precision, {fd}-decimal minutes, 1-500 m, 4000 random pairs per latitude:"] + o + [""]
    o, w = precision(broken=True, n=500)
    res += ["control: kx from cos(0) instead of cos(target latitude) (should fail at high latitude):"] + o
    txt = "\n".join(res)
    print(txt)
    open(f"{d}/check_nav.txt", "w").write(txt + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
