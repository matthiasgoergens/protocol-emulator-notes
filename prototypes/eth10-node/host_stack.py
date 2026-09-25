"""Independent host side for the eth10-node demo: builds request frames with scapy, and judges the
node's replies with scapy's parsers and zlib's CRC-32. Shares no code with the OCaml side.

    uv run --with scapy python host_stack.py gen <requests.txt> [seed] [count]
    uv run --with scapy python host_stack.py check <requests.txt> <replies.txt>

requests.txt: one line per frame: <hex incl. FCS> <expect_reply 0|1> <label>
replies.txt (written by the simulation): <index of the request it answers> <hex incl. FCS>
"""
import random
import sys
import zlib

from scapy.all import ARP, ICMP, IP, UDP, Ether, Raw, IPOption_RR, conf

conf.verb = 0

NODE_MAC = "02:00:00:00:00:10"
NODE_IP = "10.0.0.2"
HOST_MAC = "02:00:00:00:00:01"
HOST_IP = "10.0.0.1"


def with_fcs(frame: bytes) -> bytes:
    if len(frame) < 60:
        frame = frame + bytes(60 - len(frame))
    return frame + zlib.crc32(frame).to_bytes(4, "little")


def fcs_ok(frame: bytes) -> bool:
    return len(frame) >= 5 and zlib.crc32(frame[:-4]).to_bytes(4, "little") == frame[-4:]


def gen(path, seed, count):
    rnd = random.Random(seed)
    reqs = []

    def add(pkt, expect, label, raw=None):
        b = raw if raw is not None else with_fcs(bytes(pkt))
        reqs.append((b, expect, label))

    # directed cases
    add(Ether(src=HOST_MAC, dst="ff:ff:ff:ff:ff:ff") / ARP(op=1, hwsrc=HOST_MAC, psrc=HOST_IP, pdst=NODE_IP), 1, "arp-bcast")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / ARP(op=1, hwsrc=HOST_MAC, psrc=HOST_IP, pdst=NODE_IP), 1, "arp-unicast")
    add(Ether(src=HOST_MAC, dst="ff:ff:ff:ff:ff:ff") / ARP(op=1, hwsrc=HOST_MAC, psrc=HOST_IP, pdst="10.0.0.3"), 0, "arp-other-ip")
    add(Ether(src=HOST_MAC, dst="ff:ff:ff:ff:ff:ff") / ARP(op=2, hwsrc=HOST_MAC, psrc=HOST_IP, pdst=NODE_IP), 0, "arp-reply-not-request")
    for size in (0, 1, 18, 56, 100, 200):
        add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP, id=rnd.randrange(65536)) /
            ICMP(type=8, id=rnd.randrange(65536), seq=rnd.randrange(65536)) / Raw(bytes(rnd.randrange(256) for _ in range(size))),
            1, f"ping-{size}")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP, flags="DF") / ICMP(type=8, id=7, seq=1) / Raw(b"df set"), 1, "ping-df")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst="10.0.0.9") / ICMP(type=8) / Raw(b"x" * 20), 0, "ping-other-ip")
    add(Ether(src=HOST_MAC, dst="02:00:00:00:00:99") / IP(src=HOST_IP, dst=NODE_IP) / ICMP(type=8) / Raw(b"x" * 20), 0, "ping-other-mac")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP, options=[IPOption_RR()]) / ICMP(type=8) / Raw(b"opt"), 0, "ping-ip-options")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP, flags="MF") / ICMP(type=8) / Raw(b"frag" * 5), 0, "ping-fragment")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP) / ICMP(type=0) / Raw(b"reply"), 0, "icmp-echo-reply")
    add(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP) / UDP(sport=1234, dport=7) / Raw(b"udp"), 0, "udp")
    good = with_fcs(bytes(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP) / ICMP(type=8, id=1, seq=2) / Raw(b"bad fcs")))
    add(None, 0, "ping-bad-fcs", raw=good[:-1] + bytes([good[-1] ^ 0x01]))
    runt = bytes(Ether(src=HOST_MAC, dst=NODE_MAC) / IP(src=HOST_IP, dst=NODE_IP) / ICMP(type=8) / Raw(b"r"))[:40]
    add(None, 0, "runt-40", raw=runt + zlib.crc32(runt).to_bytes(4, "little"))
    # constrained random: pings with random sizes, ids, sequence numbers, TTLs, DF; some ARPs
    for k in range(count):
        if rnd.random() < 0.2:
            add(Ether(src=HOST_MAC, dst=rnd.choice(["ff:ff:ff:ff:ff:ff", NODE_MAC])) /
                ARP(op=1, hwsrc="02:00:00:00:%02x:%02x" % (rnd.randrange(256), rnd.randrange(256)),
                    psrc="10.0.%d.%d" % (rnd.randrange(256), rnd.randrange(1, 255)), pdst=NODE_IP), 1, f"rand-arp-{k}")
        else:
            size = rnd.randrange(0, 200)
            add(Ether(src=HOST_MAC, dst=NODE_MAC) /
                IP(src="10.0.%d.%d" % (rnd.randrange(256), rnd.randrange(1, 255)), dst=NODE_IP, ttl=rnd.randrange(1, 256),
                   id=rnd.randrange(65536), flags=rnd.choice(["", "DF"]), tos=rnd.randrange(256)) /
                ICMP(type=8, id=rnd.randrange(65536), seq=rnd.randrange(65536)) / Raw(bytes(rnd.randrange(256) for _ in range(size))),
                1, f"rand-ping-{k}-{size}")
    with open(path, "w") as f:
        for b, e, label in reqs:
            f.write(f"{b.hex()} {e} {label}\n")
    print(f"{len(reqs)} requests written to {path}, {sum(e for _, e, _ in reqs)} expecting a reply")


def check(req_path, rep_path):
    reqs = [(bytes.fromhex(h), int(e), label) for h, e, label in (l.split() for l in open(req_path) if l.strip())]
    reps = {}
    for line in open(rep_path):
        if line.strip():
            i, h = line.split()
            reps.setdefault(int(i), []).append(bytes.fromhex(h))
    failures = []
    ok_count = 0
    for i, (req, expect, label) in enumerate(reqs):
        got = reps.get(i, [])
        if not expect:
            if got:
                failures.append(f"{label}: replied although it must not")
            continue
        if len(got) != 1:
            failures.append(f"{label}: {len(got)} replies")
            continue
        rep = got[0]
        errs = []
        if not fcs_ok(rep):
            errs.append("FCS wrong")
        q = Ether(req[:-4])
        r = Ether(rep[:-4])
        if r.dst != q.src or r.src != NODE_MAC:
            errs.append(f"MACs {r.src}->{r.dst}")
        if ARP in q:
            if ARP not in r:
                errs.append("not ARP")
            else:
                a = r[ARP]
                if not (a.op == 2 and a.hwsrc == NODE_MAC and a.psrc == NODE_IP and a.hwdst == q[ARP].hwsrc and a.pdst == q[ARP].psrc):
                    errs.append(f"ARP fields {a.summary()}")
        else:
            if ICMP not in r or IP not in r:
                errs.append("not IP/ICMP")
            else:
                ip, ic = r[IP], r[ICMP]
                if ip.src != NODE_IP or ip.dst != q[IP].src:
                    errs.append(f"IPs {ip.src}->{ip.dst}")
                qi = q[IP]
                for fld in ("version", "ihl", "tos", "len", "id", "flags", "frag", "ttl", "proto"):
                    if getattr(ip, fld) != getattr(qi, fld):
                        errs.append(f"IP {fld} changed")
                if ic.type != 0 or ic.code != 0:
                    errs.append(f"ICMP type {ic.type}")
                if ic.id != q[ICMP].id or ic.seq != q[ICMP].seq:
                    errs.append("id/seq")
                if bytes(ic.payload) != bytes(q[ICMP].payload):
                    errs.append("payload differs")
                # checksums: let scapy recompute from scratch and compare
                ip_again = IP(bytes(ip))
                ip_sum = ip_again.chksum
                del ip_again.chksum
                if IP(bytes(ip_again)).chksum != ip_sum:
                    errs.append("IP checksum wrong")
                ic_again = ICMP(bytes(ic))
                ic_sum = ic_again.chksum
                del ic_again.chksum
                if ICMP(bytes(ic_again)).chksum != ic_sum:
                    errs.append("ICMP checksum wrong")
        if errs:
            failures.append(f"{label}: " + ", ".join(errs))
        else:
            ok_count += 1
    extra = [i for i in reps if i >= len(reqs) or i < 0]
    if extra:
        failures.append(f"replies attributed to no request: {extra}")
    n_expect = sum(e for _, e, _ in reqs)
    print(f"{ok_count} of {n_expect} expected replies correct; {len(reqs) - n_expect} requests correctly unanswered: "
          f"{len(reqs) - n_expect - sum(1 for f in failures if 'must not' in f)}")
    for f in failures[:20]:
        print("  FAIL", f)
    print("host stack verdict:", "PASS" if not failures else "FAIL")
    return 0 if not failures else 1


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1, int(sys.argv[4]) if len(sys.argv) > 4 else 20)
    else:
        sys.exit(check(sys.argv[2], sys.argv[3]))
