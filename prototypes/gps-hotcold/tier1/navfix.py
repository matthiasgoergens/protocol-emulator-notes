"""Host-side NMEA parser and hot/cold navigation in integer arithmetic (the RP2350's job; see README).

Everything here is integer: coordinates in units of 1e-5 arcminute (u), distances in centimetres,
angles as 32-bit binary angles (2^32 = one turn). The only floating point is in set_target(),
which runs once when a cache is loaded and produces two Q16 scale constants.

parse(): a byte-at-a-time state machine as the firmware runs it on the bytes the sequencer's UART
thread hands over. It checks the checksum, keeps $GPRMC (position, status, speed, course) and
$GPGGA (fix quality, satellites), and ignores everything else.
"""
import math

U_PER_DEG = 60 * 100_000          # 1e-5 arcminute units per degree
TURN = 1 << 32

# ---------------------------------------------------------------- parser

def _coord(field, hemi, is_lat, frac_digits=5):
    """'ddmm.mmmmm' -> integer units; None if empty. Fractions shorter than 5 digits are padded,
    longer ones truncated, so 4-decimal modules work too (at 10x coarser resolution)."""
    if not field or hemi not in ("N", "S", "E", "W"):
        return None
    ip, _, fp = field.partition(".")
    dw = 2 if is_lat else 3
    if len(ip) != dw + 2 or not ip.isdigit() or (fp and not fp.isdigit()):
        return None
    deg = int(ip[:dw]); mins = int(ip[dw:])
    fp = (fp + "00000")[:frac_digits]
    v = deg * U_PER_DEG + mins * 100_000 + int(fp)
    return -v if hemi in ("S", "W") else v


def _hundredths(field):
    """'123.45' -> 12345 (course in centidegrees, speed in centiknots); None if empty"""
    if not field:
        return None
    ip, _, fp = field.partition(".")
    fp = (fp + "00")[:2]
    if not (ip.isdigit() and fp.isdigit()):
        return None
    return int(ip) * 100 + int(fp)


class Parser:
    """feed(byte) -> a dict when a checked RMC sentence completes, else None.
    GGA updates quality/satellites carried into the next RMC."""

    def __init__(self):
        self.state = "idle"
        self.buf = bytearray()
        self.cs = 0
        self.cs_txt = ""
        self.quality = 0
        self.sats = 0
        self.stats = dict(sentences=0, bad_checksum=0, rmc=0, gga=0, other=0)

    def feed(self, b):
        if b == 0x24:                         # '$' always restarts
            self.state, self.buf, self.cs = "body", bytearray(), 0
            return None
        if self.state == "body":
            if b == 0x2A:                     # '*'
                self.state, self.cs_txt = "cs", ""
            elif b in (0x0D, 0x0A) or len(self.buf) > 90:
                self.state = "idle"           # no checksum: reject
            else:
                self.buf.append(b); self.cs ^= b
            return None
        if self.state == "cs":
            self.cs_txt += chr(b)
            if len(self.cs_txt) == 2:
                self.state = "idle"
                self.stats["sentences"] += 1
                try:
                    ok = int(self.cs_txt, 16) == self.cs
                except ValueError:
                    ok = False
                if not ok:
                    self.stats["bad_checksum"] += 1
                    return None
                return self._sentence(self.buf.decode("ascii", "replace"))
        return None

    def _sentence(self, s):
        f = s.split(",")
        tag = f[0][2:]
        if tag == "GGA" and len(f) >= 8:
            self.stats["gga"] += 1
            self.quality = int(f[6]) if f[6].isdigit() else 0
            self.sats = int(f[7]) if f[7].isdigit() else 0
            return None
        if tag == "RMC" and len(f) >= 9:
            self.stats["rmc"] += 1
            valid = f[2] == "A"
            return dict(time=f[1], valid=valid,
                        lat=_coord(f[3], f[4], True) if valid else None,
                        lon=_coord(f[5], f[6], False) if valid else None,
                        speed_ckn=_hundredths(f[7]), cog_cdeg=_hundredths(f[8]),
                        quality=self.quality, sats=self.sats)
        self.stats["other"] += 1
        return None


def parse(data):
    p = Parser()
    out = []
    for b in data:
        r = p.feed(b)
        if r is not None:
            out.append(r)
    return out, p.stats

# ---------------------------------------------------------------- navigation

def to_units(deg):
    return round(deg * U_PER_DEG)


def set_target(lat_deg, lon_deg):
    """once per cache: target in units, and Q16 centimetres-per-unit for north and east from the
    WGS84 meridian (M) and prime-vertical (N) radii of curvature at the target's latitude"""
    a, f = 6378137.0, 1 / 298.257223563
    e2 = f * (2 - f)
    p = math.radians(lat_deg)
    w = math.sqrt(1 - e2 * math.sin(p) ** 2)
    M = a * (1 - e2) / w ** 3
    N = a / w
    rad_per_u = math.radians(1 / U_PER_DEG)
    ky = round(M * rad_per_u * 100 * 65536)
    kx = round(N * math.cos(p) * rad_per_u * 100 * 65536)
    return dict(lat=to_units(lat_deg), lon=to_units(lon_deg), ky=ky, kx=kx)


CORDIC_N = 20
ATAN = [round(math.atan(2.0 ** -i) / (2 * math.pi) * TURN) for i in range(CORDIC_N)]
KINV_Q16 = round(65536 / math.prod(math.sqrt(1 + 2.0 ** (-2 * i)) for i in range(CORDIC_N)))
GUARD = 6
FAR_UNITS = 1 << 21          # about 39 km of latitude; beyond this the gadget just says "far"


def _mulq16(a, k):
    """signed a * unsigned Q16 k, rounded: one 32x32->64 multiply and a shift"""
    p = a * k
    return (p + (1 << 15)) >> 16


def cordic(x, y):
    """vectoring CORDIC on (north, east): returns (magnitude, binary angle of atan2(east, north))
    using only adds, subtracts and shifts, plus one Q16 multiply for the gain"""
    x <<= GUARD; y <<= GUARD
    ang = 0
    if x < 0:                                  # pre-rotate by half a turn
        x, y, ang = -x, -y, TURN // 2
    for i in range(CORDIC_N):
        if y > 0:
            x, y, ang = x + (y >> i), y - (x >> i), ang + ATAN[i]
        else:
            x, y, ang = x - (y >> i), y + (x >> i), ang - ATAN[i]
    r = _mulq16(x, KINV_Q16)
    return (r + (1 << (GUARD - 1))) >> GUARD, ang % TURN


def distance_bearing(tgt, lat, lon):
    """-> (distance cm, bearing binary angle, far flag). Local tangent plane at the target."""
    dlat = lat - tgt["lat"]
    dlon = lon - tgt["lon"]
    half = 180 * U_PER_DEG
    if dlon > half: dlon -= 2 * half
    if dlon < -half: dlon += 2 * half
    far = abs(dlat) >= FAR_UNITS or abs(dlon) >= FAR_UNITS
    if far:
        dlat = max(-FAR_UNITS, min(FAR_UNITS, dlat)); dlon = max(-FAR_UNITS, min(FAR_UNITS, dlon))
    north = -_mulq16(dlat, tgt["ky"])          # vector from the walker to the target
    east = -_mulq16(dlon, tgt["kx"])
    d, b = cordic(north, east)
    return d, b, far


def cdeg_to_ba(cdeg):
    """course over ground in centidegrees -> binary angle: (x * 2^32 / 36000) as a Q multiply"""
    return (cdeg * TURN // 36000) % TURN     # one 64-bit multiply and a divide by a constant
