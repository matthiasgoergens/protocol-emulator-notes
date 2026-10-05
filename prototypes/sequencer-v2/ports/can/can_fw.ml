(* CAN on ISA v2: the TX thread re-assembled for v2; the RX thread not ported.

   Everything of ../../../sequencer-ps2-can/can_fw.ml is kept (can_fw_orig.ml, a copy made by the
   dune rule: the frame encoder the host driver uses, the pin and timing records, the output tags,
   the faults) except [tx] and [rx].

   TX. The thread already took a stream the host had stuffed and given its CRC, so it needs none
   of the rejected engines; it used two instructions v2 encodes differently:
   - CFG 3 (cnt <- acc) is v2's EXT CNTA;
   - JC cond L (jump if the condition holds) has no one-word equivalent: v2's WAITC branches when
     its condition does NOT hold, and only at dl = 0. Both uses are rewritten with the two paths
     swapped, keeping every path's slot count (checked in the comments), and dl is 0 at both
     (they follow LDD/WAITD pads or immediate WAITP branches):
       "more: JC byte getb; pad; JMP loop; getb: IN; pad; JMP loop" becomes
       "more: WAITC byte ->nb; IN; pad; JMP loop; nb: pad; JMP loop";
       "SHI; JC acc0 eof_ok; JMP eof_err; eof_ok:" becomes "SHI; WAITC acc0 ->eof_err; eof_ok:"
       (the error path is one slot shorter, and ends the frame anyway).

   RX. Not ported: it is built on the per-thread CRC engine and stuff tracker that v2 rejected
   (SHI with crc/stf/norec, JC on crc = 0, on the stuff condition and on the last bit, CFG to load
   the polynomial and clear the state). v2's replacement is on the bit path (architecture-v0
   section 2.3 and the CAN row of section 3): the edge-tracking sampler in NRZ mode with SJW and
   hard sync (gap G6, not built), the stuff tracker (a probe, 813 um2, no model yet) and the CRC
   unit, reporting through flag inputs; the RX thread then parses fields. None of those blocks
   exists as a verified model, so there is nothing yet to port the RX thread onto. *)

include Can_fw_orig

(* a label assembler for v2 words; the result is registered as a v2 programme *)
type item = W of int | L of string | R of string * (int -> int)

let assemble ?(name = "programme") items =
  let labels = Hashtbl.create 32 in
  let pos = ref 0 in
  List.iter (function L l ->
    if Hashtbl.mem labels l then failwith ("duplicate label " ^ l);
    Hashtbl.replace labels l !pos | _ -> incr pos) items;
  if !pos > Isa2.page_len then failwith (Printf.sprintf "%s too long: %d words" name !pos);
  let prog = Array.init Isa2.page_len Isa2.halt_at in
  let pos = ref 0 in
  let find l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("no label " ^ l) in
  List.iter (function
    | L _ -> ()
    | W w -> prog.(!pos) <- w; incr pos
    | R (l, f) -> prog.(!pos) <- f (find l); incr pos) items;
  Compat.register_v2 prog, !pos, find

let jmp l = R (l, Isa2.jmp)
let jnz l = R (l, Isa2.jnz)
let waitp ~pin ~value l = R (l, fun a -> Isa2.waitp ~pin ~value ~fail:a)
let waitc ~cond l = R (l, fun a -> Isa2.waitc ~cond ~fail:a)
let delay n =
  if n < 0 then failwith (Printf.sprintf "negative delay %d" n)
  else if n = 0 then [] else if n = 1 then [ W Isa2.nop ]
  else [ W (Isa2.ldd (n - 2)); W Isa2.waitd ]
let pad = delay

(* Underrun (since 2026-10-05). The mid-frame refill IN used to wait for the host byte with the
   bit in progress, so a byte late by more than the slack lengthened a bit, and a byte that never
   came held the bus at that level for ever. Now, as in verif-oracles' 10BASE-T fix, WAITC 9 (host
   byte valid, at dl = 0) runs one slot before the IN, taking one slot of the byte path's pad;
   if no byte is there, the thread releases txd (recessive), clears the flag and reports
   OUT tag_tx 5, which a host treats like any other failed attempt. Slack: the byte must be valid
   one slot (4 clocks) earlier than the IN used to need it. [~underrun_check:false] assembles the
   earlier programme, for the stall-injection oracle's before (can_stall.ml). *)
let tx_underrun = 5

let tx ?(faults = no_faults) ?(underrun_check = true) (p : pins) (t : timing) =
  let { n; sp; _ } = t in
  let m1 x = 1 lsl x in
  let txd v = W (Isa2.setp ~mask:(m1 p.txd) ~value:v ~oe:1 ()) in
  let flag v = W (Isa2.setp ~mask:(m1 p.flag) ~value:v ~oe:1 ()) in
  if n < sp + 6 then failwith "tx: bit time too short for the sample point";
  let check =
    if faults.no_arbitration_check then [ W Isa2.nop; W Isa2.nop ]
    else [ waitp ~pin:p.txd ~value:0 "chk"; jmp "join"; L "chk"; waitp ~pin:p.rx ~value:1 "lost" ] in
  let items =
    [ txd 1; flag 0 ]
    @ [ L "txi"; W Isa2.in_; W Isa2.cnta; W Isa2.in_ ]
    @ [ L "wi"; W (Isa2.ldd (10 * n)); waitp ~pin:p.rx ~value:0 "wlast";
        L "wr"; waitp ~pin:p.rx ~value:1 "wr"; jmp "wi";
        L "wlast"; W (Isa2.ldd n); waitp ~pin:p.rx ~value:0 "start";
        flag 1; jmp "loop";
        L "start"; flag 1 ]
    @ [ L "loop"; W (Isa2.sho ~pin:p.txd ~msb:1 ()) ] @ pad (sp - 2) @ check
    @ (if faults.no_arbitration_check then [] else [ L "join" ])
    (* both paths from "more" to "loop": n - sp - 2 slots, as the original's *)
    @ [ jnz "more"; jmp "tail";
        L "more"; waitc ~cond:Isa2.c_byte "nb" ]
    @ (if underrun_check then [ waitc ~cond:Isa2.c_host "under"; W Isa2.in_ ] @ pad (n - sp - 6)
       else [ W Isa2.in_ ] @ pad (n - sp - 5))
    @ [ jmp "loop";
        L "nb" ] @ pad (n - sp - 4) @ [ jmp "loop" ]
    @ [ L "tail" ] @ pad (n - sp - 3) @ [ txd 1 ] @ pad (n + sp - 2) @ [ W (Isa2.ldd 0); waitp ~pin:p.rx ~value:0 "noack" ]
    @ [ W (Isa2.ldc 8) ] @ pad (n - 2)
    @ [ L "eof"; W (Isa2.shi ~pin:p.rx ~msb:1 ()); waitc ~cond:(Isa2.c_acc 0) "eof_err";
        L "eof_ok" ] @ pad (n - 3) @ [ jnz "eof"; flag 0; W (Isa2.outi ~tag:tag_tx 1); jmp "txi";
        L "noack"; flag 0; W (Isa2.outi ~tag:tag_tx 2) ] @ pad (9 * n) @ [ jmp "txi";
        L "eof_err"; flag 0; W (Isa2.outi ~tag:tag_tx 4); jmp "txi";
        L "lost"; txd 1; flag 0; W (Isa2.outi ~tag:tag_tx 3); jmp "txi" ]
    @ (if underrun_check then [ L "under"; txd 1; flag 0; W (Isa2.outi ~tag:tag_tx tx_underrun); jmp "txi" ] else []) in
  assemble ~name:"can tx" items

let rx ?faults:_ ?raw:_ (_ : pins) (_ : timing) : int array * int * (string -> int) =
  failwith "CAN RX is not ported to v2: it needs the bit-path assists (see can_fw.ml)"

(* The RX thread's slot in a TX-only node: hold txe recessive (the transceiver drives the bus with
   txd AND txe) and keep "flag" free for the TX thread. *)
let rx_idle (p : pins) =
  let prog, _, _ = assemble ~name:"txe holder"
      [ W (Isa2.setp ~mask:(1 lsl p.txe) ~value:1 ~oe:1 ()); L "h"; jmp "h" ] in
  prog
