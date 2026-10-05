"""Synthetic geocaching walk -> NMEA 0183 byte stream, as a u-blox NEO-6M would send it at 9600 baud.

Truth: a walk defined in local east/north metres around the target, converted to latitude and
longitude with an exact WGS84 geodesic (geographiclib), sampled at 1 Hz. GPS error: a first-order
Gauss-Markov position error (sigma 2 m per axis, tau 60 s) plus 0.7 m white noise; velocity noise
0.1 m/s per axis for speed and course over ground.

Each second carries the NEO-6M default sentence set (RMC, VTG, GGA, GSA, three GSV, GLL), so the
parser has to skip what it does not use. The first three seconds have no fix (RMC status V, GGA
quality 0). One sentence has a single bit flipped in transit, so its checksum fails.

Outputs (in the given directory): nmea.txt (the byte stream), truth.csv (per-second truth and
reported fix), walk.json (target and parameters).
Usage: walk.py OUTDIR
"""
import json, math, sys
import numpy as np
from geographiclib.geodesic import Geodesic

G = Geodesic.WGS84
TARGET = (1.344100, 103.820000)          # near MacRitchie Reservoir, Singapore (a made-up cache)
SPEED = 1.3                               # m/s walking
SEED = 20260925

# waypoints in (east, north) metres relative to the target; the walk starts ~450 m away,
# first heads the wrong way (colder), turns, zigzags in, overshoots, circles back, stands still.
WAYPOINTS = [(-380, 250), (-470, 330), (-430, 200), (-250, 150), (-180, 40), (-60, 60),
             (-20, -10), (25, -30), (10, 12), (0, 0)]
DWELL_END = 25                            # seconds standing at the cache


def path():
    pts = [np.array(p, float) for p in WAYPOINTS]
    out = []
    pos = pts[0].copy()
    for nxt in pts[1:]:
        while True:
            d = nxt - pos
            dist = np.hypot(*d)
            if dist < SPEED:
                pos = nxt.copy()
                break
            pos = pos + d / dist * SPEED
            out.append(pos.copy())
    out += [pts[-1].copy()] * DWELL_END
    return np.array(out)


def to_latlon(e, n):
    """exact geodesic from the target: azimuth atan2(e, n), distance hypot(e, n)"""
    d = math.hypot(e, n)
    if d == 0:
        return TARGET
    r = G.Direct(TARGET[0], TARGET[1], math.degrees(math.atan2(e, n)), d)
    return r["lat2"], r["lon2"]


def nmea_deg(v, is_lat):
    """ddmm.mmmmm / dddmm.mmmmm with hemisphere, rounded to 1e-5 minute as the NEO-6M prints"""
    h = ("N" if v >= 0 else "S") if is_lat else ("E" if v >= 0 else "W")
    v = abs(v)
    tot = round(v * 60 * 100000)          # integer 1e-5 minutes
    deg, rem = divmod(tot, 60 * 100000)
    mins, frac = divmod(rem, 100000)
    w = 2 if is_lat else 3
    return f"{deg:0{w}d}{mins:02d}.{frac:05d}", h


def sentence(body):
    cs = 0
    for ch in body.encode():
        cs ^= ch
    return f"${body}*{cs:02X}\r\n"


def main(outdir):
    rng = np.random.default_rng(SEED)
    track = path()
    n = len(track)
    # Gauss-Markov position error
    tau, sig = 60.0, 2.0
    a = math.exp(-1 / tau)
    gm = np.zeros((n, 2))
    gm[0] = rng.normal(0, sig, 2)
    for i in range(1, n):
        gm[i] = a * gm[i - 1] + rng.normal(0, sig * math.sqrt(1 - a * a), 2)
    meas = track + gm + rng.normal(0, 0.7, (n, 2))
    vel = np.vstack([track[1:] - track[:-1], np.zeros((1, 2))]) + rng.normal(0, 0.1, (n, 2))
    stream = []
    rows = []
    t0 = 10 * 3600 + 15 * 60                # 10:15:00 UTC
    flip_at = 57                            # second whose RMC gets a bit flip in transit
    for i in range(n):
        t = t0 + i
        hms = f"{t // 3600:02d}{t // 60 % 60:02d}{t % 60:02d}.00"
        lat, lon = to_latlon(*meas[i])
        tlat, tlon = to_latlon(*track[i])
        la, lah = nmea_deg(lat, True)
        lo, loh = nmea_deg(lon, False)
        fix = i >= 3
        spd = float(np.hypot(*vel[i]))
        cog = (math.degrees(math.atan2(vel[i][0], vel[i][1])) + 360) % 360
        kn = spd / 0.514444
        if fix:
            rmc = sentence(f"GPRMC,{hms},A,{la},{lah},{lo},{loh},{kn:.3f},{cog:.2f},250926,,,A")
            vtg = sentence(f"GPVTG,{cog:.2f},T,,M,{kn:.3f},N,{spd * 3.6:.3f},K,A")
            gga = sentence(f"GPGGA,{hms},{la},{lah},{lo},{loh},1,08,1.01,45.3,M,4.9,M,,")
            gll = sentence(f"GPGLL,{la},{lah},{lo},{loh},{hms},A,A")
        else:
            rmc = sentence(f"GPRMC,{hms},V,,,,,,,250926,,,N")
            vtg = sentence("GPVTG,,,,,,,,,N")
            gga = sentence(f"GPGGA,{hms},,,,,0,00,99.99,,,,,,")
            gll = sentence(f"GPGLL,,,,,{hms},V,N")
        gsa = sentence("GPGSA,A,3,02,05,12,13,15,18,24,25,,,,,2.01,1.01,1.73")
        gsv = [sentence("GPGSV,3,1,10,02,45,120,38,05,30,045,35,12,70,300,42,13,15,210,29"),
               sentence("GPGSV,3,2,10,15,55,080,40,18,20,330,31,24,35,170,36,25,60,020,41"),
               sentence("GPGSV,3,3,10,29,05,260,,31,08,100,")]
        sec = [rmc, vtg, gga, gsa] + gsv + [gll]
        if i == flip_at:
            b = bytearray(rmc.encode())
            b[20] ^= 0x04                   # one bit, inside the latitude field
            sec[0] = b.decode()
        stream.append("".join(sec))
        rows.append((i, t, fix, tlat, tlon, lat, lon, la + lah, lo + loh, kn, cog, i == flip_at))
    text = "".join(stream)
    with open(f"{outdir}/nmea.txt", "w", newline="") as f:
        f.write(text)
    with open(f"{outdir}/truth.csv", "w") as f:
        f.write("i,utc_s,fix,true_lat,true_lon,rep_lat,rep_lon,nmea_lat,nmea_lon,knots,cog,corrupted\n")
        for r in rows:
            f.write(",".join(f"{x:.9f}" if isinstance(x, float) else str(x) for x in r) + "\n")
    per_sec = [len(s) for s in stream]
    meta = dict(target=TARGET, seconds=n, bytes=len(text), max_bytes_per_second=max(per_sec),
                uart_load_9600=max(per_sec) * 10 / 9600, seed=SEED, flip_at=flip_at)
    json.dump(meta, open(f"{outdir}/walk.json", "w"), indent=1)
    print(json.dumps(meta))


if __name__ == "__main__":
    main(sys.argv[1])
