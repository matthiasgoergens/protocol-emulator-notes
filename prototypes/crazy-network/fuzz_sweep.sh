#!/usr/bin/env bash
# Seed variance on the crazy network: 10 seeds each for fuzzing and the random baseline, 10,000
# executions per campaign, one at a time (each uses 16 cores). Waits for the hwfuzz sweep first.
cd "$(dirname "$0")"
while pgrep --full 'sweep_packet.sh|bench.exe sweep' > /dev/null; do sleep 60; done
eval "$(opam env --switch=5.3.0 --set-switch)"
for seed in $(seq 31 40); do
  for mode in fuzz random; do
    nice ionice ./_build/default/main.exe fuzz 10000 $mode $seed > out/fuzz_${mode}_$seed.log 2>&1
    uv run queue_eval.py out/fuzz_${mode}_$seed 2>/dev/null | grep --invert-match Installed >> out/fuzz_sweep_eval.txt
  done
done
