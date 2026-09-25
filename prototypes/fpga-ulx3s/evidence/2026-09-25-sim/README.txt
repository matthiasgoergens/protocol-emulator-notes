Simulated runs of the ULX3S test bench, 2026-09-25, on the Verilator model of rtl/emu_core.v with
the C++ board models of sim/sim_main.cpp. Base commit in base-commit.txt; files that were
modified but not yet committed at run time are listed in uncommitted-at-run.txt (the runs used
the working tree, which is committed together with this directory).

cpb60/, cpb60.log      uv run host/emu_runner.py --sim --cpb 60 --controls   (board's UART divider)
cpb8/, cpb8.log        uv run host/emu_runner.py --sim --cpb 8 --controls
                       both: 16 tests pass, 2 negative controls fail as required -> "18 of 18 as expected"
board-judge-issi-flash/  --sim --judge board --sim-flash-id 9D6018 --only flash_id,rtc_ack,uart_loop,uart_jumper
                       a simulated board whose flash differs from the model, judged as a board: passes
strict-judge-issi-flash/ the same flash_id run judged in strict simulation mode: the whole-trace prediction
                       FAILS at cycle 883 (MISO differs from the model's Winbond ID). Expected; the log says BAD
                       because the runner expected a pass.
control-mcp7940n-trace-as-pcf8523.txt  an rtc_ack trace (MCP7940N at 0x6F) checked against the PCF8523 test: FAILS, as it must
interlock-mutant/      flash_interlock control against a mutant with the RTL interlock disabled: FAILS, as it must
Each test directory holds <test>.trace (as dumped by the 'T' command), <test>.capture, <test>.check.txt
(the checker's report) and <test>.sim.log (the simulator's stderr), plus summary.json.
