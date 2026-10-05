"""Check crc_oracle.exe's combine against zlib, an independent implementation.

For each "pair" line: zlib.crc32 of a ++ b (the direct CRC, computed by zlib) and libz's
crc32_combine(crc_a, crc_b, len_b) must both equal our combine. For each "big" line (lengths up
to 2^60, where no direct CRC can be computed): libz's crc32_combine must equal ours.
Run: uv run --no-project python zlib_check.py VECTORS
"""
import ctypes
import ctypes.util
import sys
import zlib

libz = ctypes.CDLL(ctypes.util.find_library("z"))
libz.crc32_combine.restype = ctypes.c_ulong
libz.crc32_combine.argtypes = [ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int64]  # z_off_t is 64-bit here
libz.zlibVersion.restype = ctypes.c_char_p
assert libz.crc32_combine(zlib.crc32(b"1234"), zlib.crc32(b"56789"), 5) == zlib.crc32(b"123456789") == 0xCBF43926

pairs = bigs = bad = 0
for line in open(sys.argv[1]):
    f = line.split()
    if f[0] == "pair":
        a = b"" if f[1] == "-" else bytes.fromhex(f[1])
        b = b"" if f[2] == "-" else bytes.fromhex(f[2])
        ca, cb, lb, ours = map(int, f[3:7])
        pairs += 1
        if not (zlib.crc32(a) == ca and zlib.crc32(b) == cb and zlib.crc32(a + b) == ours
                and libz.crc32_combine(ca, cb, lb) == ours):
            bad += 1
            print("MISMATCH", line.strip())
    else:
        ca, cb, lb, ours = map(int, f[1:5])
        bigs += 1
        if libz.crc32_combine(ca, cb, lb) != ours:
            bad += 1
            print("MISMATCH", line.strip())
print(f"zlib {libz.zlibVersion().decode()}: {pairs} split vectors (zlib.crc32 of the whole and libz crc32_combine), "
      f"{bigs} large-length vectors (crc32_combine): {bad} mismatches -> {'PASS' if bad == 0 else 'FAIL'}")
sys.exit(1 if bad else 0)
