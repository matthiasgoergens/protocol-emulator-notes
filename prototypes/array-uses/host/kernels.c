/* Host (RP2350, Cortex-M33) inner loops for every candidate workload, written as the best
   plain algorithm I know for a microcontroller (bit-packed where the data is one bit, DSP SIMD
   where it is 16 bit). Compiled by host/run_mca.sh and timed statically with llvm-mca's
   Cortex-M33 model. Each function's innermost loop is the "item" named in the comment; the
   array side of the comparison is in ../evaluate.py.

   Nothing here runs on an RP2350. The numbers are a static pipeline model of one core with
   single-cycle SRAM, no bus contention and no interrupts. */
#include <stdint.h>
#include <arm_acle.h>

static inline uint32_t popc(uint32_t v) {          /* M33 has no popcount instruction */
  v = v - ((v >> 1) & 0x55555555u);
  v = (v & 0x33333333u) + ((v >> 2) & 0x33333333u);
  v = (v + (v >> 4)) & 0x0f0f0f0fu;
  return (v * 0x01010101u) >> 24;
}

/* K1 item: one 32-bit word = 32 one-bit x one-bit MACs (XOR + popcount), one lag.
   GPS tracking on 1-bit samples, binary neural layers, brute-force code search. */
int32_t k1_corr_bitpacked(const uint32_t *s, const uint32_t *c, int n) {
  int32_t acc = 0;
  for (int i = 0; i < n; i++) acc += popc(s[i] ^ c[i]);
  return acc;
}

/* K1b item: one 32-bit word, Harley-Seal carry-save popcount (the fast way): accumulates
   3 words per carry-save step; the item is one word of the stream. */
int32_t k1b_corr_harley_seal(const uint32_t *s, const uint32_t *c, int n) {
  uint32_t ones = 0, twos = 0; int32_t acc = 0;
  for (int i = 0; i + 1 < n; i += 2) {
    uint32_t a = s[i] ^ c[i], b = s[i + 1] ^ c[i + 1];
    uint32_t u = ones ^ a; uint32_t twosa = (ones & a) | (u & b); ones = u ^ b;
    acc += popc(twos & twosa); twos ^= twosa;
  }
  return 4 * acc + 2 * popc(twos) + popc(ones);
}

/* K2 item: two 16-bit samples x two +-1 code values (SMLAD, dual MAC).
   Multi-bit samples against a +-1 code: DSSS, soft-decision matcher. */
int32_t k2_pm1_smlad(const int16_t *x, const int16_t *code, int n) {
  int32_t acc = 0;
  const uint32_t *xx = (const uint32_t *)x, *cc = (const uint32_t *)code;
  for (int i = 0; i < n / 2; i++) acc = __smlad(xx[i], cc[i], acc);
  return acc;
}

/* K3 item: one 8-bit ADC sample through a square-wave-LO I/Q mixer and a third-order CIC's
   three integrators per arm (32-bit wrapping). The digital down-converter of an SDR. */
void k3_cic_ddc(const int8_t *x, int n, uint32_t k, uint32_t *st) {
  uint32_t ph = st[0], i1 = st[1], i2 = st[2], i3 = st[3], q1 = st[4], q2 = st[5], q3 = st[6];
  for (int j = 0; j < n; j++) {
    int32_t v = x[j];
    int32_t vi = ((int32_t)ph < 0) ? -v : v;
    int32_t vq = ((int32_t)(ph + 0x40000000u) < 0) ? -v : v;
    ph += k;
    i1 += vi; i2 += i1; i3 += i2;
    q1 += vq; q2 += q1; q3 += q2;
  }
  st[0] = ph; st[1] = i1; st[2] = i2; st[3] = i3; st[4] = q1; st[5] = q2; st[6] = q3;
}

/* K4 item: one 32-bit word of a periodic 1-bit capture folded into bit-sliced vertical
   counters (synchronous averaging; early exit when the carry dies). TDR, sampling scope. */
void k4_fold(const uint32_t *w, int n, uint32_t planes[][8], int L_words) {
  int p = 0;
  for (int i = 0; i < n; i++) {
    uint32_t carry = w[i];
    uint32_t *pl = planes[p];
    for (int b = 0; b < 8 && carry; b++) { uint32_t t = pl[b] & carry; pl[b] ^= carry; carry = t; }
    if (++p == L_words) p = 0;
  }
}

/* K5 item: one text character against a pattern of up to 32 characters (Myers 1999
   bit-vector edit distance): 32 DP cells per item. */
int k5_myers(const uint8_t *t, int n, const uint32_t *peq, int m) {
  uint32_t pv = ~0u, mv = 0, hi = 1u << (m - 1); int score = m, best = m;
  for (int j = 0; j < n; j++) {
    uint32_t eq = peq[t[j]];
    uint32_t xv = eq | mv, xh = (((eq & pv) + pv) ^ pv) | eq;
    uint32_t ph = mv | ~(xh | pv), mh = pv & xh;
    score += (ph & hi) ? 1 : 0; score -= (mh & hi) ? 1 : 0;
    ph = (ph << 1) | 1; mh <<= 1;
    pv = mh | ~(xv | ph); mv = ph & xv;
    if (score < best) best = score;
  }
  return best;
}

/* K6 item: one Viterbi butterfly (2 add-compare-selects) of a K = 7, rate 1/2 code with
   16-bit metrics and packed decision bits. 32 butterflies per decoded bit. */
void k6_viterbi_step(const int16_t *old, int16_t *nw, const int16_t *bm, uint32_t *dec) {
  uint32_t d = 0;
  for (int i = 0; i < 32; i++) {
    int16_t m = bm[i];
    int16_t a0 = old[i] + m, b0 = old[i + 32] - m;
    int16_t a1 = old[i] - m, b1 = old[i + 32] + m;
    int s0 = b0 < a0, s1 = b1 < a1;
    nw[2 * i] = s0 ? b0 : a0; nw[2 * i + 1] = s1 ? b1 : a1;
    d |= (uint32_t)(s0 | (s1 << 1)) << ((2 * i) & 31);
    if ((i & 15) == 15) { dec[i >> 4] = d; d = 0; }
  }
}

/* K7 item: one dynamic-time-warping cell, D = |x - t| + min(left, up, diagonal). */
void k7_dtw_row(const int16_t *t, int m, int16_t x, const int16_t *prev, int16_t *cur) {
  int16_t left = 0x3fff;
  for (int j = 1; j <= m; j++) {
    int16_t d = x - t[j - 1]; if (d < 0) d = -d;
    int16_t a = prev[j], b = prev[j - 1];
    int16_t mn = a < b ? a : b; mn = mn < left ? mn : left;
    left = d + mn; cur[j] = left;
  }
}

/* K8 item: two min-plus relaxations d[j] = min(d[j], dik + dk[j]) with saturating 16-bit
   SIMD (UQADD16, USUB16 + SEL). Floyd-Warshall's inner loop; shortest paths. */
void k8_minplus(uint16_t *d, const uint16_t *dk, uint16_t dik, int n) {
  uint32_t dd = (uint32_t)dik * 0x10001u;
  uint32_t *dv = (uint32_t *)d; const uint32_t *kv = (const uint32_t *)dk;
  for (int j = 0; j < n / 2; j++) {
    uint32_t s = __uqadd16(dd, kv[j]);
    __usub16(s, dv[j]);                 /* sets GE flags where s >= d */
    dv[j] = __sel(dv[j], s);
  }
}

/* K9 item: one voice sample of wavetable synthesis with amplitude and mixing. */
int32_t k9_voices(uint32_t *ph, const uint32_t *inc, const int16_t *amp, const int16_t *tab, int nv) {
  int32_t mix = 0;
  for (int v = 0; v < nv; v++) {
    ph[v] += inc[v];
    mix += (tab[ph[v] >> 24] * amp[v]) >> 8;
  }
  return mix;
}

/* K10 item: 32 cells of an elementary cellular automaton (rule 110), bit-sliced. */
void k10_rule110(const uint32_t *a, uint32_t *b, int n) {
  uint32_t prev = 0;
  for (int i = 0; i < n; i++) {
    uint32_t c = a[i], nx = (i + 1 < n) ? a[i + 1] : 0;
    uint32_t l = (c << 1) | (prev >> 31), r = (c >> 1) | (nx << 31);
    b[i] = (c | r) & ~(l & c & r);
    prev = c;
  }
}

/* K11 item: one Mandelbrot iteration in Q4.28 fixed point (SMULL). */
int k11_mandel(int32_t cr, int32_t ci, int maxit) {
  int32_t x = 0, y = 0; int it = 0;
  for (; it < maxit; it++) {
    int32_t x2 = (int32_t)(((int64_t)x * x) >> 28), y2 = (int32_t)(((int64_t)y * y) >> 28);
    if (x2 + y2 > (4 << 28) - 1 || x2 + y2 < 0) break;
    int32_t xy = (int32_t)(((int64_t)x * y) >> 27);
    x = x2 - y2 + cr; y = xy + ci;
  }
  return it;
}

/* K12 item: one received symbol into one Reed-Solomon syndrome over GF(256), Horner with
   log/antilog tables: S <- S * alpha^i + r. */
void k12_rs_syndrome(const uint8_t *r, int n, uint8_t *S, int i, const uint8_t *lg, const uint8_t *ex) {
  uint8_t s = *S;
  for (int j = 0; j < n; j++) {
    s = (s ? ex[lg[s] + i] : 0) ^ r[j];     /* ex[] is doubled to 510 entries: no modulo */
  }
  *S = s;
}

/* K13 item: one message bit through one candidate CRC-16 polynomial (bitwise). Brute-force
   polynomial search. */
uint16_t k13_crc_bitwise(const uint8_t *bits, int n, uint16_t poly) {
  uint16_t c = 0;
  for (int j = 0; j < n; j++) {
    uint16_t fb = (uint16_t)(((c >> 15) ^ bits[j]) & 1);
    c = (uint16_t)(c << 1) ^ (fb ? poly : 0);
  }
  return c;
}

/* K14 item: one DDA step of a grid raycaster (Wolfenstein style). */
int k14_dda(int32_t sdx, int32_t sdy, int32_t ddx, int32_t ddy, int mx, int my, int stx, int sty,
            const uint8_t *map) {
  for (;;) {
    if (sdx < sdy) { sdx += ddx; mx += stx; } else { sdy += ddy; my += sty; }
    if (map[(my << 6) | mx]) return mx | (my << 8);
  }
}

/* K15 item: one byte compared at one candidate position of an LZ77 window (the naive search
   the array would parallelise; a hash chain on the host visits few positions). */
int k15_lz_match(const uint8_t *win, const uint8_t *look, int maxlen) {
  int l = 0;
  while (l < maxlen && win[l] == look[l]) l++;
  return l;
}

/* K16 item: 8 PDM bits into a first CIC stage via a 256-entry popcount table (the usual
   microcontroller PDM decimator's first step). */
int32_t k16_pdm(const uint8_t *b, int n, const uint8_t *pc) {
  int32_t i1 = 0, i2 = 0;
  for (int j = 0; j < n; j++) { i1 += pc[b[j]]; i2 += i1; }
  return i2;
}

/* K17 item: one insertion of a new value into a sorted 16-entry list (sliding median /
   top-k); the loop item is one compare-shift step. */
void k17_insert(int16_t *a, int n, int16_t v) {
  int j = n - 1;
  while (j > 0 && a[j - 1] > v) { a[j] = a[j - 1]; j--; }
  a[j] = v;
}
