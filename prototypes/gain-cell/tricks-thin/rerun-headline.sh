#!/bin/sh
# headline configurations again with the start-up-safe measurement (from=25 ns), to check that
# dropping the VLO grid level in life.py changed nothing
cd "$(dirname "$0")"
./pod.sh hold-lv-vlo0.3-bar0.1-v2 cell.py VLO=0.3 VBAR=0.1
./pod.sh hold-lv-vlo0.3-bar0.1-park-v2 cell.py VLO=0.3 VBAR=0.1 WBLH=0.3
./pod.sh hold-lv-vlo0.25-bar0.1-v2 cell.py VLO=0.25 VBAR=0.1
./pod.sh hold-lv-vlo0.25-bar0.1-park-v2 cell.py VLO=0.25 VBAR=0.1 WBLH=0.25
