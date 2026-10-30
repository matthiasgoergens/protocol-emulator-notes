# Plant a stuck-at-0 on one top-level output of the hardened netlist: the driving cell's .X is
# disconnected onto a dummy wire and the port is tied to 0.  Usage: plant.py NETLIST 'uo_out[0]'
import sys

path, port = sys.argv[1], sys.argv[2]
s = open(path).read()
pin = f".X({port}))"
assert s.count(pin) == 1, pin
s = s.replace(pin, ".X(planted_float));")
assert s.count(" input clk;\n") == 1
s = s.replace(" input clk;\n", " input clk;\n wire planted_float;\n", 1)
s = s.replace("endmodule", f" assign {port} = 1'b0;\nendmodule", 1)
open(path, "w").write(s)
