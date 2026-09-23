#!/usr/bin/env bash
# 20,000 executions per run; fuzzing against the random baseline, two seeds each, two runs at a time.
cd "$(dirname "$0")"
eval "$(opam env --switch=5.3.0 --set-switch)"
for seed in 21 22; do
  nice ionice ./_build/default/main.exe fuzz 20000 random $seed > out/fuzz_random_$seed.log 2>&1 &
  nice ionice ./_build/default/main.exe fuzz 20000 fuzz $seed > out/fuzz_fuzz_$seed.log 2>&1 &
  wait
done
for d in out/fuzz_random_21 out/fuzz_fuzz_21 out/fuzz_random_22 out/fuzz_fuzz_22; do uv run queue_eval.py $d; done > out/fuzz_eval.txt 2>&1
