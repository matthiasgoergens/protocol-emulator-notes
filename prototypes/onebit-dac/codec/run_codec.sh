#!/bin/sh
# Test streams from the synthetic clip (results/wav/source_44k1.wav), the reference decoders,
# and our decoders (sim/main.exe adpcm | sbc). Every comparison is cmp of raw s16le PCM.
# Writes results/codec/references.txt; the streams live in the scratch directory.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
E=$HERE/../sim/_build/default/main.exe
W=${ONEBIT_SCRATCH:-/var/tmp/onebit-dac}/codec
mkdir --parents "$W"; cd "$W"
cp "$HERE/../results/wav/source_44k1.wav" music.wav
au2raw() { python3 -c "
d=open('$1','rb').read(); off=int.from_bytes(d[4:8],'big'); b=bytearray(d[off:])
b[0::2],b[1::2]=d[off+1::2],d[off::2]; open('$2','wb').write(b)"; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
ff -i music.wav -f au -acodec pcm_s16be music.au
ff -i music.wav -ar 48000 -f au -acodec pcm_s16be music48.au
sbcenc -s 8 -B 16 -j -b 53 music.au > a2dp_j53.sbc
sbcenc -s 8 -B 16 -b 35 -S music.au > s8_snr35.sbc
sbcenc -s 4 -B 8 -d -b 20 music.au > s4_dual20.sbc
sbcenc -s 8 -B 16 -j -b 51 music48.au > a2dp48_j51.sbc
ff -i music.wav -c:a adpcm_ima_wav ima.wav
ff -i ima.wav -f s16le ima.ref.raw
{
  echo "ffmpeg: $(ffmpeg -version | sed --quiet 1p); BlueZ $(sbcenc --help 2>&1 | sed --quiet 1p)"
  nice ionice $E adpcm ima.wav ima.ours.raw
  if cmp ima.ours.raw ima.ref.raw; then echo "IMA ADPCM: bit-exact with ffmpeg ($(stat --format=%s ima.ref.raw) bytes)"; fi
  for f in a2dp_j53 s8_snr35 s4_dual20 a2dp48_j51; do
    echo "== $f: $(sbcinfo $f.sbc | grep --extended-regexp 'Subbands|Block|Sampling|Channel mode|Allocation|Bitpool|Number of frames' | tr '\n\t' '  ')"
    sbcdec -f $f.ref.au $f.sbc; au2raw $f.ref.au $f.ref.raw
    ff -f sbc -i $f.sbc -f s16le $f.ff.raw
    cmp $f.ref.raw $f.ff.raw && echo "$f: sbcdec and ffmpeg agree bit for bit"
    nice ionice $E sbc $f.sbc $f.ours.raw pe
    cmp $f.ours.raw $f.ref.raw && echo "$f: OUR DECODER (CRC on the PE array model) bit-exact with both ($(stat --format=%s $f.ref.raw) bytes)"
  done
  nice ionice $E sbc s4_dual20.sbc s4_dual20.rtl.raw pe-rtl
  cmp s4_dual20.rtl.raw s4_dual20.ref.raw && echo "s4_dual20: bit-exact with the CRC on the PE model and the Hardcaml RTL in lockstep"
  nice ionice $E sbc-controls a2dp_j53.sbc
} > "$HERE/../results/codec/references.txt" 2>&1
cat "$HERE/../results/codec/references.txt"
