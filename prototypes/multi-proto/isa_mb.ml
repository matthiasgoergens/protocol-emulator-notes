(* Mailbox variant of the deadline-sequencer ISA: executable specification.

   A strict extension of ../deadline-sequencer/isa.ml (which is not modified). Everything there
   still holds: four hardware threads issue round-robin, one instruction per cycle, every
   instruction takes exactly one slot, nothing stalls. What is added is a way for threads to talk
   to each other and to generic hardware blocks without going through the host or the pins, and a
   data-dependent branch.

   Parameters (fixed at generation time):
     pc_bits  6 reproduces the base ISA's 64-word programmes; 7 gives 128 words per thread (the
              intended 1024x16 SRAM macro would give 256). Every address field below is the low
              pc_bits of the word, so with pc_bits = 6 bits 6..11 of JMP/JNZ/WAITP words are
              ignored exactly as in the base ISA.
     depth    entries per inbox, 1, 2 or 4.

   New state: one inbox per thread, a FIFO of [depth] bytes. Since only one instruction executes
   per cycle, at most one inbox operation happens per cycle in the whole core, so the inboxes need
   no arbitration and no second port: the barrel schedule is the arbiter.

   New instructions (opcodes 0xE and 0xF were NOP, and still are on master as of 2026-09-25):

     E MBX   dir[11] ch[10:8] 0[7] fail[pc_bits-1:0]
             ch 0..3 names inbox ch; ch 4..7 names generic port ch-4 (outside the core).
             dir = 0, SEND: if the target can accept (inbox not full / out-port ready), push acc
               and proceed; else if dl = 0 jump to fail; else stay (retry next slot).
             dir = 1, RECV: if the source has a byte (inbox not empty / in-port valid), pop it
               into acc and proceed; else if dl = 0 jump to fail; else stay.
     F WAITC val[11] cond[10:7] fail[pc_bits-1:0]
             proceed when condition bit = val; else if dl = 0 jump to fail; else stay.
             cond 0..7: acc bit cond; 8..11: inbox (cond-8) is full; 12..15: flag input (cond-12).
             With dl = 0 and an acc bit this is a conditional branch in one slot:
               WAITC val=0 cond=k fail=L  branches to L when acc bit k is 1.
             With dl > 0 on an acc bit it is a branch taken when the deadline expires (acc cannot
             change while waiting), which is a timed branch, not an accident.

   Timing rules, the point of the design:
     - A blocked SEND/RECV/WAITC occupies only its own thread's slot, exactly like WAITP. The
       round-robin schedule never changes, so no mailbox state can move another thread's edges.
     - Every wait has the thread's deadline as its bound, so a full or empty mailbox cannot hang
       a thread unless the programme asks for that explicitly with fail = own address (an
       unbounded wait, which the assembler can flag).
     - Coupling between threads is only through the inboxes and ports a programme names, and
       through pins it reads. A thread that names no shared channel is timing-identical whatever
       its neighbours do; the isolation tests check this.

   One more addition, for full-duplex shifting (SPI, JTAG): SHO gains a capture option in bits
   that are unused in the base ISA and on master:
     7 SHO   pin[11:9] msb[8] od[7] cap[6] cpin[5:3]
             as before, and with cap set the pin cpin is sampled in the same slot and enters the
             bit the shift vacates (msb: bit 0; lsb: bit 7). One shift per bit, out and in, so a
             byte exchange is SHO then seven SHO-with-capture then SHI. Without it the two shifts
             lose a bit, and full duplex needs the pin sampler.

   Ports: in-port k presents (valid, data); a RECV pops it with a one-cycle ready pulse, like IN.
   Out-port k presents ready; a SEND pushes acc, visible as (valid one-hot, data) registered, like
   OUT. Flags are four level inputs from generic blocks.

   Faults for testing the checkers (interpreter only): Drop_push n silently loses the n-th
   successful push into any inbox (the SEND still proceeds); Lifo pops the newest entry;
   Swap_pair n holds the n-th push back and delivers it after the next push to the same inbox. *)

let n_threads = 4

type fault = No_fault | Drop_push of int | Lifo | Swap_pair of int
type cfg = { pc_bits : int; depth : int; fault : fault }

let cfg ?(pc_bits = 7) ?(depth = 2) ?(fault = No_fault) () = { pc_bits; depth; fault }
let prog_len c = 1 lsl c.pc_bits

(* Assembler helpers for the new instructions (addresses up to 7 bits). *)
let a7 a = a land 0x7F
let send ~ch ~fail = (0xE lsl 12) lor ((ch land 7) lsl 8) lor a7 fail
let recv ~ch ~fail = (0xE lsl 12) lor (1 lsl 11) lor ((ch land 7) lsl 8) lor a7 fail
let waitc ~cond ~value ~fail = (0xF lsl 12) lor ((value land 1) lsl 11) lor ((cond land 15) lsl 7) lor a7 fail
(* branch to [l] if acc bit k is 1 / 0 (requires dl = 0 to be immediate) *)
let br_set ~bit ~target = waitc ~cond:bit ~value:0 ~fail:target
let br_clr ~bit ~target = waitc ~cond:bit ~value:1 ~fail:target
let cond_full i = 8 + i
let cond_flag i = 12 + i
(* 7-bit address versions of the base ISA's control words *)
let jmp a = (9 lsl 12) lor a7 a
let jnz a = (10 lsl 12) lor a7 a
let waitp ~pin ~value ~fail = (5 lsl 12) lor ((pin land 7) lsl 9) lor ((value land 1) lsl 8) lor a7 fail
(* SHO with capture: out on [pin], in from [cpin], msb first by default *)
let shx ?(msb = 1) ~pin ~cpin () = (7 lsl 12) lor ((pin land 7) lsl 9) lor (msb lsl 8) lor (1 lsl 6) lor ((cpin land 7) lsl 3)

type state = {
  c : cfg;
  pcs : int array; accs : int array; cnts : int array; dls : int array;
  mutable pin_out : int; mutable pin_oe : int; mutable thread : int;
  inbox : int list array;          (* oldest first *)
  mutable pushes : int;            (* successful inbox pushes so far, for Drop_push *)
  mutable held : (int * int) option;   (* Swap_pair: the push held back *)
  mutable swapped : (int * int) option;   (* Swap_pair: the two bytes that were exchanged *)
}

let init c = {
  c; pcs = Array.make n_threads 0; accs = Array.make n_threads 0; cnts = Array.make n_threads 0;
  dls = Array.make n_threads 0; pin_out = 0; pin_oe = 0; thread = 0;
  inbox = Array.make n_threads []; pushes = 0; held = None; swapped = None;
}

type io = {
  pin_in : int; host_in : int; host_in_valid : bool;
  port_in : int array; port_in_valid : bool array;   (* 4 in-ports *)
  port_out_ready : bool array;                        (* 4 out-ports *)
  flags : int;                                        (* 4 flag bits *)
}

let idle_io = { pin_in = 0; host_in = 0; host_in_valid = false; port_in = Array.make 4 0;
                port_in_valid = Array.make 4 false; port_out_ready = Array.make 4 false; flags = 0 }

type effects = {
  host_out : int option; host_in_ready : bool;
  port_pop : int option;              (* in-port popped this cycle *)
  port_push : (int * int) option;     (* (out-port, byte) pushed this cycle *)
  mb : [ `Push of int * int | `Pop of int * int | `None ];   (* inbox traffic, for tracing *)
}

let counts st = Array.map List.length st.inbox

let step st ~(mem : int array array) (io : io) =
  let c = st.c in
  let t = st.thread in
  let plen = prog_len c in
  let pc = st.pcs.(t) and acc = st.accs.(t) and cnt = st.cnts.(t) and dl = st.dls.(t) in
  let instr = mem.(t).(pc) in
  let opc = (instr lsr 12) land 0xF in
  let imm12 = instr land 0xFFF and imm8 = instr land 0xFF in
  let pin = (instr lsr 9) land 7 and pin_val = (instr lsr 8) land 1 in
  let addr = instr land (plen - 1) in
  let od = (instr lsr 7) land 1 in
  let mask8 = (instr lsr 4) land 0xFF and setv = (instr lsr 3) land 1 and seto = (instr lsr 2) land 1 in
  let pin_bit = (io.pin_in lsr pin) land 1 in
  let pc_next = ref ((pc + 1) land (plen - 1)) in
  let acc_next = ref acc and cnt_next = ref cnt in
  let dl_next = ref (if dl = 0 then 0 else dl - 1) in
  let host_out = ref None and host_in_ready = ref false in
  let port_pop = ref None and port_push = ref None and mb = ref `None in
  let stay () = pc_next := pc in
  let fail_or_stay () = if dl = 0 then pc_next := addr else stay () in
  let set_pin_bit v = st.pin_out <- (st.pin_out land lnot (1 lsl pin)) lor (v lsl pin) in
  let full i = List.length st.inbox.(i) >= c.depth in
  (match opc with
   | 1 ->
     st.pin_out <- (st.pin_out land lnot mask8) lor (if setv = 1 then mask8 else 0);
     st.pin_oe <- (st.pin_oe land lnot mask8) lor (if seto = 1 then mask8 else 0)
   | 2 -> cnt_next := imm12
   | 3 -> dl_next := imm12
   | 4 -> acc_next := imm8
   | 5 -> if pin_bit <> pin_val then fail_or_stay ()
   | 6 -> if dl <> 0 then stay ()
   | 7 ->
     let b = if pin_val = 1 then (acc lsr 7) land 1 else acc land 1 in
     if od = 1 then begin
       set_pin_bit 0;
       st.pin_oe <- (st.pin_oe land lnot (1 lsl pin)) lor ((1 - b) lsl pin)
     end else set_pin_bit b;
     let cap = (instr lsr 6) land 1 and cbit = (io.pin_in lsr ((instr lsr 3) land 7)) land 1 in
     acc_next := (if pin_val = 1 then ((acc lsl 1) land 0xFF) lor (cap land cbit) else (acc lsr 1) lor ((cap land cbit) lsl 7));
     cnt_next := (cnt - 1) land 0xFFF
   | 8 ->
     acc_next := (if pin_val = 1 then ((acc lsl 1) land 0xFF) lor pin_bit else (acc lsr 1) lor (pin_bit lsl 7));
     cnt_next := (cnt - 1) land 0xFFF
   | 9 -> pc_next := addr
   | 10 -> if cnt <> 0 then pc_next := addr
   | 11 -> host_out := Some acc
   | 12 -> if io.host_in_valid then (acc_next := io.host_in; host_in_ready := true) else stay ()
   | 13 -> stay ()
   | 14 ->
     let is_recv = (instr lsr 11) land 1 = 1 and ch = (instr lsr 8) land 7 in
     if not is_recv then begin
       if ch >= 4 then begin
         if io.port_out_ready.(ch - 4) then port_push := Some (ch - 4, acc) else fail_or_stay ()
       end else if not (full ch) then begin
         st.pushes <- st.pushes + 1;
         let dropped = (match c.fault with Drop_push n -> st.pushes = n | _ -> false) in
         (match c.fault, st.held with
          | Swap_pair n, _ when st.pushes = n -> st.held <- Some (ch, acc)
          | Swap_pair _, Some (hc, hv) when hc = ch -> st.inbox.(ch) <- st.inbox.(ch) @ [ acc; hv ]; st.held <- None; st.swapped <- Some (hv, acc)
          | _ -> if not dropped then st.inbox.(ch) <- st.inbox.(ch) @ [ acc ]);
         mb := `Push (ch, acc)
       end else fail_or_stay ()
     end else begin
       if ch >= 4 then begin
         if io.port_in_valid.(ch - 4) then (acc_next := io.port_in.(ch - 4); port_pop := Some (ch - 4)) else fail_or_stay ()
       end else (match st.inbox.(ch) with
         | [] -> fail_or_stay ()
         | q ->
           let v, rest = (match c.fault with
             | Lifo -> let r = List.rev q in List.hd r, List.rev (List.tl r)
             | _ -> List.hd q, List.tl q) in
           acc_next := v; st.inbox.(ch) <- rest; mb := `Pop (ch, v))
     end
   | 15 ->
     let v = (instr lsr 11) land 1 and cond = (instr lsr 7) land 15 in
     let bit =
       if cond < 8 then (acc lsr cond) land 1
       else if cond < 12 then (if full (cond - 8) then 1 else 0)
       else (io.flags lsr (cond - 12)) land 1 in
     if bit <> v then fail_or_stay ()
   | _ -> ());
  st.pcs.(t) <- !pc_next; st.accs.(t) <- !acc_next; st.cnts.(t) <- !cnt_next; st.dls.(t) <- !dl_next;
  st.thread <- (t + 1) mod n_threads;
  { host_out = !host_out; host_in_ready = !host_in_ready; port_pop = !port_pop; port_push = !port_push; mb = !mb }
