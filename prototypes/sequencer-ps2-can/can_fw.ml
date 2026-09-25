(* Classic CAN (2.0A) as firmware on the deadline sequencer, ISA variant v.

   A node is two threads:

   - RX thread, the node's bit timing and bit stream processor: hard sync on SOF, resynchronisation
     on recessive-to-dominant edges with a window of +-SJW (WAITP with a deadline), destuffing and
     CRC-15 in the variant's stuff tracker and CRC engine, DLC dispatch as a branch tree, ACK,
     error flags for stuff, CRC and form errors. It reports everything to the host with tagged OUT.
   - TX thread: drives a bit stream that the host driver has stuffed and given a CRC, one bit per
     bit time from its own hard sync, and at each sample point checks a recessive bit against the
     bus: reading dominant means arbitration lost (or a bit error), and it stops driving at once.
     Then the ACK slot and EOF, and a status for the host driver, which retransmits.

   Pins per node: rx (bus, in), txd (TX thread, push-pull, 1 = recessive), txe (RX thread's ACK and
   error flags, push-pull), flag (TX thread -> RX thread: "this node is transmitting", so the RX
   thread does not acknowledge its own frame). The transceiver drives the bus with txd AND txe.

   Timing is in slots (one instruction per thread, four clocks). N = bit time, SP = sample point,
   SJW = resynchronisation jump width, all in slots. Every path below is balanced by the
   generator; the comments give slot offsets.

   RX output (host_out tag, value):
     1 SOF        (value 0)
     0 DATA       destuffed frame bits, msb first, packed as: 3 bits (SOF ID10 ID9), 8 bits
                  (ID8..ID1), 8 bits (ID0 RTR IDE r0 DLC3..0), then the data and CRC bits
                  (8 * bytes + 15 of them) as 7 bits followed by 8-bit chunks
     2 CRC        1 = CRC matched, 0 = CRC error
     3 ACK        bit 0 = bus level in the ACK slot (0 = acknowledged)
     4 END        0 ok, 1 stuff error, 2 CRC error, 3 form error, 5 extended frame (unsupported)
     6 RAW        (option raw) every sampled bit: bit 0 = level; value 0x80 marks a stuff bit
   TX output: tag 5, value 1 acknowledged, 2 no acknowledge, 3 lost arbitration or bit error,
     4 error during EOF. *)

open Sim.Asm

type pins = { rx : int; txd : int; txe : int; flag : int }
type timing = { n : int; sp : int; sjw : int }

let tag_data = 0 and tag_sof = 1 and tag_crc = 2 and tag_ack = 3 and tag_end = 4 and tag_tx = 5 and tag_raw = 6

(* faults for the controls *)
type faults = { no_resync : bool; bad_poly : bool; no_arbitration_check : bool }
let no_faults = { no_resync = false; bad_poly = false; no_arbitration_check = false }

let pad n = delay n

(* ------------------------------------------------------------------ RX thread *)

let rx ?(faults = no_faults) ?(raw = false) (p : pins) (t : timing) =
  let { n; sp; sjw } = t in
  let nb = n - sp in
  let m1 x = 1 lsl x in
  let txe v = W (Isa_v.setp ~mask:(m1 p.txe) ~value:v ~oe:1) in
  let shi_data = W (Isa_v.shi ~crc:1 ~stf:1 ~pin:p.rx ~msb:1 ()) in
  let shi_stuff = W (Isa_v.shi ~stf:1 ~norec:1 ~pin:p.rx ~msb:1 ()) in
  let shi_plain = W (Isa_v.shi ~pin:p.rx ~msb:1 ()) in
  let raw_bit = if raw then [ W (Isa_v.out ~tag:tag_raw ()) ] else [] in
  let raw_stuff = if raw then [ W (Isa_v.outi ~tag:tag_raw 0x80) ] else [] in
  let r = List.length raw_bit in   (* slots the raw option adds after each sample *)
  (* The front end for the bit after a sample (p = 0 at the previous SHI, nominal start nb):
     three paths join label [dst] at B' + SP - k, where B' is the resynchronised bit start. The
     caller has spent [p0] slots after the SHI. *)
  let front ~name ~p0 ~k ~dst =
    let l s = name ^ "_" ^ s in
    let m = sp - k - sjw - 4 in
    if m < 0 then failwith (Printf.sprintf "%s: sample point too early for k=%d (m=%d)" name k m);
    if faults.no_resync then
      (* control: no resynchronisation at all, sample at the nominal time *)
      [ jc ~cond:Isa_v.cond_last1 (l "rs") ] @ pad (n - k - p0 - 2) @ [ jmp dst; L (l "rs") ] @ pad (n - k - p0 - 2) @ [ jmp dst ]
    else
      [ jc ~cond:Isa_v.cond_last1 (l "rs") ]
      (* previous bit dominant: no edge can come, sample at the nominal time *)
      @ pad (n - k - p0 - 2) @ [ jmp dst ]
      (* previous bit recessive: window [nb - sjw, nb + sjw] *)
      @ [ L (l "rs") ] @ pad (nb - sjw - 1 - (p0 + 1)) @ [ W (Isa_v.ldd (2 * sjw)); waitp ~pin:p.rx ~value:0 (l "to") ]
      @ pad (sp - k - 2) @ [ jmp dst ]
      (* no edge by nb + sjw: watch until the sample point for a late edge *)
      @ [ L (l "to"); W (Isa_v.ldd m); waitp ~pin:p.rx ~value:0 (l "now"); W Isa_v.waitd ] @ pad sjw @ [ jmp dst ]
      @ [ L (l "now"); jmp dst ] in
  (* A stuffed field F: SHI at F_shi; after it the stuff check, then the front end to F_bk, the
     bookkeeping for the bit just recorded (byte output, count, field exit), then F_shi again.
     [exit] is the not-taken path of the count, taking [x] slots to the next field's sample. *)
  let field ~name ~exit ~x =
    let l s = name ^ "_" ^ s in
    let k = 3 + x in
    let post = 1 + r in   (* slots after the SHI before the stuff check: SHI + raw OUT *)
    [ L (l "shi"); shi_data ] @ raw_bit
    @ [ jc ~cond:Isa_v.cond_stuff (l "st") ]
    @ front ~name:(l "d") ~p0:(post + 1) ~k ~dst:(l "bk")
    (* the stuff bit: sampled like any bit, not recorded; still a stuff condition = six equal bits *)
    @ [ L (l "st") ] @ front ~name:(l "s") ~p0:(post + 1) ~k:0 ~dst:(l "sshi")
    @ [ L (l "sshi"); shi_stuff ] @ raw_stuff
    @ [ jc ~cond:Isa_v.cond_stuff "err_stuff" ]
    (* after a stuff bit the state is that of the data front end at the same offset: share its
       resynchronisation window, keep only the dominant path *)
    @ (if faults.no_resync then front ~name:(l "sd") ~p0:(1 + r + 1) ~k ~dst:(l "bk")
       else [ jc ~cond:Isa_v.cond_last1 (l "d_rs") ] @ pad (n - k - (2 + r) - 2) @ [ jmp (l "bk") ])
    (* bookkeeping, k = 3 + x slots, ends at F_shi *)
    @ [ L (l "bk"); jc ~cond:Isa_v.cond_byte (l "ob"); W Isa_v.nop; jnz (l "c") ] @ exit
    @ [ L (l "ob"); W (Isa_v.out ~tag:tag_data ()); jnz (l "c") ] @ exit
    (* taken path: x slots to this field's SHI, the jmp back being the last of them *)
    @ [ L (l "c") ] @ pad (x - 1) @ [ jmp (l "shi") ] in
  (* DLC dispatch, entered by a jmp (1 slot); constant time: every leaf reaches its target's SHI
     [tree_t] slots after entry *)
  let depth_max = 6 in
  let tree_t = 1 + depth_max + 2 in
  (* data and CRC are one field: 8 * min(DLC, 8) + 15 bits (none of data for a remote frame) *)
  let leaf ~depth ~bytes = pad (depth_max - depth) @ [ W (Isa_v.ldc (8 * bytes + 15)); jmp "body_shi" ] in
  let rec dlc_tree bits depth value =
    match bits with
    | [] -> leaf ~depth ~bytes:value
    | b :: rest ->
      let lbl = Printf.sprintf "dlc_%d_%d" b value in
      [ jc ~cond:(Isa_v.cond_acc b) lbl ] @ dlc_tree rest (depth + 1) value
      @ [ L lbl ] @ (if b = 3 then leaf ~depth:(depth + 1) ~bytes:8 else dlc_tree rest (depth + 1) (value lor (1 lsl b))) in
  let tree =
    [ L "tree"; jc ~cond:(Isa_v.cond_acc 6) "rtr"; jc ~cond:(Isa_v.cond_acc 5) "ext" ]
    @ dlc_tree [ 3; 2; 1; 0 ] 2 0
    @ [ L "rtr" ] @ leaf ~depth:1 ~bytes:0 in
  let poly = if faults.bad_poly then 0x8B33 else 0x8B32 in   (* CRC-15 0x4599, left aligned *)
  let n6 = 6 * n in
  let items =
    [ W (Isa_v.poly_lo (poly land 0xFF)); W (Isa_v.poly_hi (poly lsr 8)); txe 1 ]
    (* bus integration: 11 recessive bit times *)
    @ [ L "rec"; W (Isa_v.ldd (11 * n)); waitp ~pin:p.rx ~value:0 "idle"; L "rec_w"; waitp ~pin:p.rx ~value:1 "rec_w"; jmp "rec" ]
    @ [ L "idle"; W (Isa_v.crc_clear ~last:1 ~mode:0 ~limit:5 ()); W (Isa_v.ldc 19); W (Isa_v.ldd 0);
        L "iw"; waitp ~pin:p.rx ~value:0 "iw";
        (* hard sync: this slot is the bit start *)
        W (Isa_v.outi ~tag:tag_sof 0) ] @ pad (sp - 3) @ [ jmp "hdr_shi" ]
    (* header: SOF .. DLC, 19 bits; exit to the DLC tree *)
    @ field ~name:"hdr" ~exit:[ jmp "tree" ] ~x:tree_t
    @ tree
    @ [ L "ext"; W (Isa_v.outi ~tag:tag_end 5); jmp "rec" ]
    (* data and CRC: exit to the delimiter *)
    @ field ~name:"body" ~exit:[ jmp "del_shi" ] ~x:1
    (* CRC delimiter at p = 0 *)
    @ [ L "del_shi"; shi_plain; jc ~cond:(Isa_v.cond_acc 0) "del_ok"; jmp "err_form";
        L "del_ok"; jc ~cond:Isa_v.cond_crc0 "crc_ok";
        (* CRC error (p3): no ACK; error flag from the bit after the ACK delimiter *)
        W (Isa_v.outi ~tag:tag_crc 0) ] @ pad (3 * n - sp - 4) @ [ txe 0 ] @ pad (n6 - 1) @ [ txe 1;
        W (Isa_v.outi ~tag:tag_end 2); jmp "rec";
        L "crc_ok"; W (Isa_v.outi ~tag:tag_crc 1); W (Isa_v.ldd 0); waitp ~pin:p.flag ~value:0 "own" ]
    (* p6: acknowledge from the ACK slot's start to its end *)
    @ pad (nb - 6) @ [ txe 0 ] @ pad (sp - 1) @ [ shi_plain; W (Isa_v.out ~tag:tag_ack ()) ] @ pad (nb - 2) @ [ txe 1 ]
    @ pad (sp - 3) @ [ jmp "eof" ]
    @ [ L "own" ] @ pad (n - 6) @ [ shi_plain; W (Isa_v.out ~tag:tag_ack ()) ] @ pad (n - 4) @ [ jmp "eof" ]
    (* ACK delimiter and EOF: eight recessive bits, SHI at p = 2N, 3N, ... *)
    @ [ L "eof"; W (Isa_v.ldc 8); L "eof_shi"; shi_plain; jc ~cond:(Isa_v.cond_acc 0) "eof_ok"; jmp "err_form";
        L "eof_ok" ] @ pad (n - 3) @ [ jnz "eof_shi"; W (Isa_v.outi ~tag:tag_end 0); jmp "idle" ]
    (* error flags: six dominant bits from the next bit start, then wait for the bus to be idle *)
    @ [ L "err_stuff" ] @ pad (nb - 2 - r) @ [ txe 0 ] @ pad (n6 - 1) @ [ txe 1; W (Isa_v.outi ~tag:tag_end 1); jmp "rec" ]
    @ [ L "err_form" ] @ pad (nb - 3) @ [ txe 0 ] @ pad (n6 - 1) @ [ txe 1; W (Isa_v.outi ~tag:tag_end 3); jmp "rec" ] in
  assemble ~name:"can rx" items

(* ------------------------------------------------------------------ TX thread *)

let tx ?(faults = no_faults) (p : pins) (t : timing) =
  let { n; sp; _ } = t in
  let m1 x = 1 lsl x in
  let txd v = W (Isa_v.setp ~mask:(m1 p.txd) ~value:v ~oe:1) in
  let flag v = W (Isa_v.setp ~mask:(m1 p.flag) ~value:v ~oe:1) in
  if n < sp + 6 then failwith "tx: bit time too short for the sample point";
  let check =
    if faults.no_arbitration_check then [ W Isa_v.nop; W Isa_v.nop ]
    else [ waitp ~pin:p.txd ~value:0 "chk"; jmp "join"; L "chk"; waitp ~pin:p.rx ~value:1 "lost" ] in
  let items =
    [ txd 1; flag 0 ]
    @ [ L "txi"; W Isa_v.in_; W Isa_v.ldca; W Isa_v.in_ ]
    (* bus idle: ten recessive bit times, then the eleventh: a SOF seen in it is joined *)
    @ [ L "wi"; W (Isa_v.ldd (10 * n)); waitp ~pin:p.rx ~value:0 "wlast";
        L "wr"; waitp ~pin:p.rx ~value:1 "wr"; jmp "wi";
        L "wlast"; W (Isa_v.ldd n); waitp ~pin:p.rx ~value:0 "start";
        (* join a SOF someone else started: our stream's SOF bit goes out one slot later *)
        flag 1; jmp "loop";
        L "start"; flag 1 ]
    (* one bit per N slots: SHO at p0, check at SP *)
    @ [ L "loop"; W (Isa_v.sho ~pin:p.txd ~msb:1 ()) ] @ pad (sp - 2) @ check
    @ (if faults.no_arbitration_check then [] else [ L "join" ])
    @ [ jnz "more"; jmp "tail";
        L "more"; jc ~cond:Isa_v.cond_byte "getb" ] @ pad (n - sp - 4) @ [ jmp "loop";
        L "getb"; W Isa_v.in_ ] @ pad (n - sp - 5) @ [ jmp "loop" ]
    (* tail at p = SP + 3 of the last CRC bit: delimiter from p = N, ACK slot sampled at 2N + SP *)
    @ [ L "tail" ] @ pad (n - sp - 3) @ [ txd 1 ] @ pad (n + sp - 2) @ [ W (Isa_v.ldd 0); waitp ~pin:p.rx ~value:0 "noack" ]
    (* ACK delimiter and EOF: eight recessive bits; SHI only counts *)
    @ [ W (Isa_v.ldc 8) ] @ pad (n - 2)
    @ [ L "eof"; W (Isa_v.shi ~pin:p.rx ~msb:1 ()); jc ~cond:(Isa_v.cond_acc 0) "eof_ok"; jmp "eof_err";
        L "eof_ok" ] @ pad (n - 3) @ [ jnz "eof"; flag 0; W (Isa_v.outi ~tag:tag_tx 1); jmp "txi";
        L "noack"; flag 0; W (Isa_v.outi ~tag:tag_tx 2) ] @ pad (9 * n) @ [ jmp "txi";
        L "eof_err"; flag 0; W (Isa_v.outi ~tag:tag_tx 4); jmp "txi";
        L "lost"; txd 1; flag 0; W (Isa_v.outi ~tag:tag_tx 3); jmp "txi" ] in
  assemble ~name:"can tx" items

(* ------------------------------------------------------------------ host driver side *)

(* The frame as the TX thread needs it: SOF through CRC, stuffed, packed msb first, preceded by
   its length. Written here for the driver; the reference model has its own encoder. *)
type frame = { id : int; rtr : bool; dlc : int; data : int list }

let crc15 bits =
  List.fold_left (fun crc b ->
    let fb = b lxor ((crc lsr 14) land 1) in
    ((crc lsl 1) land 0x7FFF) lxor (if fb = 1 then 0x4599 else 0)) 0 bits

let bits_of v w = List.init w (fun i -> (v lsr (w - 1 - i)) land 1)

let unstuffed f =
  let nbytes = if f.rtr then 0 else min f.dlc 8 in
  let body = [ 0 ] @ bits_of f.id 11 @ [ (if f.rtr then 1 else 0); 0; 0 ] @ bits_of f.dlc 4
             @ List.concat_map (fun b -> bits_of b 8) (List.filteri (fun i _ -> i < nbytes) f.data) in
  body @ bits_of (crc15 body) 15

(* stuff after five equal bits; [drop_stuff k] omits the k-th stuff bit (control) *)
let stuff ?(drop_stuff = -1) bits =
  let out = ref [] and last = ref (-1) and run = ref 0 and k = ref 0 in
  List.iter (fun b ->
    out := b :: !out;
    if b = !last then incr run else (last := b; run := 1);
    if !run = 5 then begin
      if !k <> drop_stuff then out := (1 - b) :: !out;
      incr k;
      if !k - 1 <> drop_stuff then (last := 1 - b; run := 1) else run := 0
    end) bits;
  List.rev !out

let tx_bytes ?drop_stuff ?(flip_crc = false) f =
  let u = unstuffed f in
  let u = if flip_crc then List.mapi (fun i b -> if i = List.length u - 1 then 1 - b else b) u else u in
  let s = stuff ?drop_stuff u in
  let l = List.length s in
  let first = if l mod 8 = 0 then 8 else l mod 8 in
  let arr = Array.of_list s in
  let chunk start len = let v = ref 0 in for i = 0 to len - 1 do v := (!v lsl 1) lor arr.(start + i) done;
    !v lsl (8 - len) in
  let rec chunks start = if start >= l then [] else chunk start 8 :: chunks (start + 8) in
  l :: chunk 0 first :: chunks first
