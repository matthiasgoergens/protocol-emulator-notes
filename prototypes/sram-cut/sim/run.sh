#!/bin/sh
# Run a simulation script of this directory in the spice-retention container (ngspice 44.2 + PSP 103
# OSDI), with its own work directory /var/tmp/spice-sram-cut/RUN.
#   ./run.sh RUN script.py [args...]      (environment: JOBS=N parallel ngspice processes, default 4)
set -eu
run=$1; shift
mkdir --parents /var/tmp/spice-sram-cut/"$run"
exec nice ionice --class 3 podman run --rm \
  --volume "$HOME"/.ciel/ihp-sg13g2/ihp-sg13g2:/pdk:ro \
  --volume /var/tmp/spice-sram-cut/"$run":/work \
  --volume /var/tmp/spice-sram-cut/osdi:/osdi:ro \
  --volume "$(dirname "$(readlink --canonicalize "$0")")":/src:ro \
  --env JOBS="${JOBS:-4}" --env HV="${HV:-}" --env VWL="${VWL:-1.2}" --env VBL="${VBL:-1.2}" --env PYTHONPATH=/src --workdir /work \
  spice-retention:latest python3 -u "/src/$@"
