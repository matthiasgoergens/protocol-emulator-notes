(* S/PDIF receive on generic blocks:

     pins, four samples per clock (the four-phase input stage)
       -> edge-tracking sampler in biphase-mark mode (../eth10-node/edge_sampler.ml, its verified
          RTL, unchanged), configured so that a preamble's 3-UI run ends a "burst"
       -> packer (the pin sampler's packing, ../pin-sampler/model.ml: LSB first into 16-bit words
          with a count, 0 = full; a partial word is flushed at the end of a frame, here at the
          sampler's burst end), a FIFO of four words, read by a thread on in-port 0 as three bytes
          per word: count, low, high
       -> firmware on two ISA v2 threads (R0 parser, R1 channel-status collector).

   Why the burst end finds the preambles. Biphase mark has edges 1 or 2 UI apart; only the
   preambles have 3-UI runs (AES3 2.4: they "violate the biphase-mark code rules"). With holdoff
   between 1 and 2 UI (an edge that soon after the anchor is a mid-cell edge) and timeout between
   2 and 3 UI, the sampler ends a burst inside every preamble, and the next edge starts a new one.
   The timeout counts from the last anchoring (cell-boundary) edge, not from the last edge, so a
   1-UI step does not restart it. Through the sampler's rules (traced on the model, README) the
   preambles give, between burst ends:
     B (Z) 11101000: a 1-bit segment "1", then the 28 data bits d4..d31;
     M (X) 11100010: an empty segment, then "1" d4..d31 (29 bits);
     W (Y) 11100100: a 1-bit segment "0", then d4..d31 (28 bits).
   So a count-1 word names B (it holds 1) or W (it holds 0) and is followed by a full word and a
   12-bit word; M is a full word and a 13-bit word. The parity of a segment's bits must be 0 for
   B and W and 1 for M (its prefix bit; d4..d31 have even parity by the parity bit). The
   channel-status bit d30 is bit 2 of the last byte (bit 3 for M).

   One sampler configuration covers 44.1 and 48 kHz at 60 MHz (and 60.852 MHz) with four samples
   per clock: holdoff 61 sub-samples, timeout 101 (see README for the margins). 32 kHz needs its
   own: its 2 UI equal 48 kHz's 3 UI. *)

let holdoff_default = 61
let timeout_default = 101

let sampler_cfg ?(holdoff = holdoff_default) ?(timeout = timeout_default) () =
  { Edge_sampler.mode = Biphase_mark; holdoff; timeout; offset = 0; period = 0; invert = false }

(* ---- packer ---- *)
type packer = {
  words : (int * int) Queue.t;   (* (word, count) *)
  mutable w : int; mutable n : int; mutable byte_idx : int; mutable overflows : int; mutable pushed : int;
}

let packer () = { words = Queue.create (); w = 0; n = 0; byte_idx = 0; overflows = 0; pushed = 0 }
let fifo_depth = 4

let push_word pk cnt =
  if Queue.length pk.words >= fifo_depth then pk.overflows <- pk.overflows + 1
  else begin Queue.push (pk.w, cnt) pk.words; pk.pushed <- pk.pushed + 1 end;
  pk.w <- 0; pk.n <- 0

let pack_bit pk b =
  pk.w <- pk.w lor ((b land 1) lsl pk.n); pk.n <- pk.n + 1;
  if pk.n = 16 then push_word pk 0

let pack_end pk = if pk.n > 0 then push_word pk pk.n

(* in-port 0: the next byte of the head word: count, low, high *)
let port_byte pk = match Queue.peek_opt pk.words with
  | None -> None
  | Some (w, c) -> Some (match pk.byte_idx with 0 -> c | 1 -> w land 0xff | _ -> (w lsr 8) land 0xff)

let port_pop pk =
  pk.byte_idx <- pk.byte_idx + 1;
  if pk.byte_idx = 3 then begin ignore (Queue.pop pk.words); pk.byte_idx <- 0 end

(* ---- firmware ---- *)
open Asm

let tag_data = 1 and tag_status = 2 and tag_count_err = 3 and tag_block = 4 and tag_prefix_err = 5

type kind = KB | KM | KW
let kname = function KB -> "B" | KM -> "M" | KW -> "W"
let kcode = function KB -> 1 | KM -> 2 | KW -> 3
let cpos = function KB -> 2 | KM -> 3 | KW -> 2
let expected_parity = function KB | KW -> 0 | KM -> 1

(* one byte from in-port 0 through to the host, its parity folded into the state *)
let pbyte ~name ~p ~k =
  [ L (Printf.sprintf "%s_p%d" name p); recv_w 4; i (Isa2.out ~tag:tag_data ());
    i (Isa2.bank 0); i Isa2.ldb; waitc_else (Isa2.c_acc 0) (k p); jmp (k (1 - p)) ]

let tail_code kd p =
  let n s = Printf.sprintf "t%s_%s" (kname kd) s in
  let hi q = Printf.sprintf "t%s_hi_p%d" (kname kd) q in
  (* low byte of the last word, in parity p *)
  pbyte ~name:(n "lo") ~p ~k:hi

let tail_hi kd q =
  let n s = Printf.sprintf "t%s_%s_p%d" (kname kd) s q in
  let bflag = if kd = KB then 0x80 else 0 in
  let fin r = Printf.sprintf "t%s_end_p%d" (kname kd) r in
  [ L (Printf.sprintf "t%s_hi_p%d" (kname kd) q); recv_w 4; i (Isa2.out ~tag:tag_data ()); send_w 1;
    waitc_else (Isa2.c_acc (cpos kd)) (n "c0");
    lda (bflag lor 1); send_w 0; jmp (n "par");
    L (n "c0"); lda bflag; send_w 0;
    L (n "par"); recv_w 1; i (Isa2.bank 0); i Isa2.ldb; waitc_else (Isa2.c_acc 0) (fin q); jmp (fin (1 - q)) ]

let tail_end kd r =
  let bad = if r = expected_parity kd then 0 else 1 in
  [ L (Printf.sprintf "t%s_end_p%d" (kname kd) r); i (Isa2.outi ~tag:tag_status (kcode kd lor (bad lsl 2))); jmp "f0" ]

let r0_program =
  let w1 kind =   (* the full first word, then the count of the second *)
    let n s = Printf.sprintf "w1%s_%s" kind s in
    pbyte ~name:(n "lo") ~p:0 ~k:(fun p -> Printf.sprintf "%s_p%d" (n "hi") p)
    @ pbyte ~name:(n "hi") ~p:0 ~k:(fun p -> Printf.sprintf "%s_p%d" (n "cnt") p)
    @ pbyte ~name:(n "hi") ~p:1 ~k:(fun p -> Printf.sprintf "%s_p%d" (n "cnt") p) in
  let dispatch kind p =
    let n s = Printf.sprintf "w1%s_%s" kind s in
    [ L (Printf.sprintf "%s_p%d" (n "cnt") p); recv_w 4 ]
    @ (match kind with
       | "B" -> [ i (Isa2.skne 12); jmp (Printf.sprintf "tB_lo_p%d" p) ]
       | "W" -> [ i (Isa2.skne 12); jmp (Printf.sprintf "tW_lo_p%d" p) ]
       | _ -> [ i (Isa2.skne 13); jmp (Printf.sprintf "tM_lo_p%d" p) ])
    @ [ jmp "err" ] in
  [ L "f0"; recv_w 4; i (Isa2.skne 0); jmp "w10_lo_p0"; i (Isa2.skne 1); jmp "bpre"; jmp "err";
    L "err"; i (Isa2.out ~tag:tag_count_err ()); recv_w 4; recv_w 4; jmp "f0";
    (* a 1-bit segment: 1 = B, 0 = W; then its (zero) high byte *)
    L "bpre"; recv_w 4; i (Isa2.skne 1); jmp "pB"; i (Isa2.skne 0); jmp "pW";
    i (Isa2.out ~tag:tag_prefix_err ()); recv_w 4; jmp "f0";
    L "pB"; recv_w 4; recv_w 4; i (Isa2.skne 0); jmp "w1B_lo_p0"; jmp "err";
    L "pW"; recv_w 4; recv_w 4; i (Isa2.skne 0); jmp "w1W_lo_p0"; jmp "err" ]
  @ w1 "0" @ w1 "B" @ w1 "W"
  @ dispatch "0" 0 @ dispatch "0" 1 @ dispatch "B" 0 @ dispatch "B" 1 @ dispatch "W" 0 @ dispatch "W" 1
  @ List.concat_map (fun kd -> List.concat_map (fun p -> tail_code kd p @ tail_hi kd p @ tail_end kd p) [ 0; 1 ]) [ KB; KM; KW ]

let r1_program =
  let half me other ~lo ~page ~id =
    let n s = me ^ "_" ^ s in
    [ L (n "loop"); recv_w 0; waitc_else 7 (n "st"); jmp ("to" ^ other);
      L (n "st"); i Isa2.stb; i (Isa2.shi ~pin:7 ~msb:1 ()); jnz (n "loop");
      L (n "full"); recv_w 0; waitc_else 7 (n "full"); jmp ("to" ^ other);
      (* entering [me]: the buffer [other] is complete; this code byte is the first entry *)
      L ("to" ^ me); send_w 2; i (Isa2.outi ~tag:tag_block (if id = 0 then 1 else 0)); lda lo; i (Isa2.bank page);
      i (Isa2.ldc 384); recv_w 2; i Isa2.stb; i (Isa2.shi ~pin:7 ~msb:1 ()); jmp (n "loop") ] in
  [ L "start"; lda 0; i (Isa2.bank 1); i (Isa2.ldc 384); jmp "A_loop" ]
  @ half "A" "B" ~lo:0 ~page:1 ~id:0 @ half "B" "A" ~lo:0x80 ~page:2 ~id:1

let buffer_base = function 0 -> 256 | _ -> 640

let bank_image () =
  let b = Array.make Isa2.bank_len 0 in
  for x = 0 to 255 do b.(x) <- Iec60958.parity_of x done;
  b

let store () =
  let w0, _ = assemble r0_program and w1, _ = assemble r1_program in
  let mem = Array.make Isa2.store_len 0 in
  Array.blit w0 0 mem 0 (Array.length w0);
  Array.blit w1 0 mem 256 (Array.length w1);
  mem.(512) <- Isa2.jmp 0;
  (mem, Array.length w0, Array.length w1)

(* ---- the run ---- *)
type event = { clock : int; tag : int; byte : int; snapshot : int array option }

type run_result = {
  events : event array;
  overflows : int; sampler_overruns : int; bursts : int; words : int;
  rtl_model_mismatch : int;     (* clocks where the sampler RTL and its model disagree *)
  clocks : int; prog_words : int * int;
}

type sampler_impl = Rtl | Model | Both

let run ?(impl = Rtl) ?(scfg = sampler_cfg ()) ~(samples : int array) () =
  let mem, n0, n1 = store () in
  let st = Isa2.init ~boot:[| (0, 0); (1, 0); (2, 0); (2, 0) |] ~bank:(bank_image ()) () in
  let pk = packer () in
  let sim =
    if impl = Model then None else begin
      let s = Hardcaml.Cyclesim.create (Edge_sampler.circuit ~n:4) in
      Edge_sampler.set_cfg s scfg;
      Hardcaml.Cyclesim.in_port s "active" := Hardcaml.Bits.vdd;
      Some s
    end in
  let mst = Edge_sampler.init () in
  let events = ref [] and overruns = ref 0 and bursts = ref 0 and mism = ref 0 in
  let clocks = Array.length samples in
  for c = 0 to clocks - 1 do
    (* the sampler: this clock's four samples; outputs describe them (the RTL registers them) *)
    let (v, b, en, ov) =
      let model () =
        let o = Edge_sampler.step_clock scfg mst ~active:true (List.init 4 (fun p -> (samples.(c) lsr p) land 1)) in
        (o.valid, (if o.valid then o.bit else 0), o.burst_end, o.overrun) in
      match sim with
      | None -> model ()
      | Some s ->
        Hardcaml.Cyclesim.in_port s "samples" := Hardcaml.Bits.of_int ~width:4 samples.(c);
        Hardcaml.Cyclesim.cycle s;
        let g n = Hardcaml.Bits.to_int !(Hardcaml.Cyclesim.out_port s n) in
        let r = (g "valid" = 1, (if g "valid" = 1 then g "bit" else 0), g "burst_end" = 1, g "overrun" = 1) in
        if impl = Both then (let m = model () in if m <> r then begin incr mism; if !mism <= 5 then (let (a,b,c',d) = m and (a2,b2,c2,d2) = r in Printf.eprintf "sampler mismatch at %d: model v%b b%d e%b o%b, rtl v%b b%d e%b o%b\n" c a b c' d a2 b2 c2 d2) end);
        r in
    if v then pack_bit pk b;
    if en then (incr bursts; pack_end pk);
    if ov then incr overruns;
    (* the threads *)
    let pb = port_byte pk in
    let io = Isa2.io ~port_in:[| Option.value pb ~default:0; 0; 0; 0 |] ~port_in_valid:[| pb <> None; false; false; false |] 0 in
    let e = Isa2.step st ~mem io in
    (match e.port_pop with Some 0 -> port_pop pk | _ -> ());
    (match e.host_out with
     | Some (tag, byte) ->
       let snapshot = if tag = tag_block then (let base = buffer_base byte in Some (Array.sub st.bankmem base 384)) else None in
       events := { clock = c; tag; byte; snapshot } :: !events
     | None -> ())
  done;
  { events = Array.of_list (List.rev !events); overflows = pk.overflows; sampler_overruns = !overruns; bursts = !bursts;
    words = pk.pushed; rtl_model_mismatch = !mism; clocks; prog_words = (n0, n1) }

(* ---- host side: subframes from the event stream ---- *)
type rx_subframe = { kind : kind; slots : int; parity_bad : bool; at : int }

type decoded = {
  subframes : rx_subframe list;
  count_errors : int; prefix_errors : int; short_records : int;
  cs_blocks : (int * int array * int array) list;   (* (clock, left 192 bits, right 192 bits), complete blocks only *)
}

let decode (r : run_result) =
  let bytes = ref [] and sfs = ref [] and ce = ref 0 and pe = ref 0 and short = ref 0 and blocks = ref [] in
  let seen_block = ref false in
  Array.iter (fun ev ->
      if ev.tag = tag_data then bytes := ev.byte :: !bytes
      else if ev.tag = tag_status then begin
        (match !bytes with
         | [ h2; l2; h1; l1 ] ->
           let kind = match ev.byte land 3 with 1 -> KB | 2 -> KM | _ -> KW in
           let w1 = l1 lor (h1 lsl 8) and w2 = l2 lor (h2 lsl 8) in
           let seg = w1 lor (w2 lsl 16) in
           let skip = match kind with KB | KW -> 0 | KM -> 1 in
           let d = (seg lsr skip) land 0xfffffff in
           sfs := { kind; slots = d lsl 4; parity_bad = ev.byte land 4 <> 0; at = ev.clock } :: !sfs
         | _ -> incr short);
        bytes := []
      end else if ev.tag = tag_count_err then (incr ce; bytes := [])
      else if ev.tag = tag_prefix_err then (incr pe; bytes := [])
      else if ev.tag = tag_block then begin
        (match ev.snapshot with
         | Some s when !seen_block ->
           blocks := (ev.clock, Array.init 192 (fun f -> s.(2 * f) land 1), Array.init 192 (fun f -> s.((2 * f) + 1) land 1)) :: !blocks
         | _ -> ());
        seen_block := true
      end) r.events;
  { subframes = List.rev !sfs; count_errors = !ce; prefix_errors = !pe; short_records = !short; cs_blocks = List.rev !blocks }
