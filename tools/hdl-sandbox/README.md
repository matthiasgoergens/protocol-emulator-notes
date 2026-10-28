# hdl-sandbox

A container for simulating and model-checking HDL we did not write (other entries' RTL and the
counterexamples Aristotle returns for it): no network, the sources read-only, an unprivileged user.

    podman build --tag hdl-sandbox:trixie tools/hdl-sandbox
    podman run --rm --network=none --volume SRC:/src:ro,Z --volume OUT:/out:Z hdl-sandbox:trixie \
        iverilog -g2012 -o /out/sim /src/top.v /src/tb.v
