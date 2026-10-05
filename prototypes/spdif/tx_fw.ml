(* S/PDIF transmit firmware for the ISA v2 sequencer (../sequencer-v2/isa2.ml), and the harness
   that runs it against the NCO pacer and a sample source.

   Division of work (all generic blocks):
   - thread T0 builds each subframe as 8 bytes of UI transitions (64 UIs, MSB first) and SENDs
     them to out-port 0, the pacer's FIFO (pacer.ml: NRZI coder, NCO pacing on the quarter grid);
   - thread T1 walks the channel-status table in the bank and hands T0 one code byte per frame
     through inbox 0 (bit 0 = C of the left subframe, bit 1 = C of the right, bit 7 = frame 0 of
     the block, i.e. preamble B instead of M);
   - the samples come from in-port 0 as four bytes per frame (left low, left high, right low,
     right high). In the demo that port is the tap of the PE segment running the synthesiser,
     stepped once per frame by the feed word T0 SENDs to out-port 1; in the tests it is the host.

   The sequencer has no ALU: no XOR, no shift by a variable, no add. Everything bit-level is a
   table in the data bank (1,024 bytes), indexed by BANK (bp <- {page, acc}) and LDB:
     page 0  lo_expand[x]: x's bits 0..3 as four biphase-mark symbols in the transition domain,
             1 b0 1 b1 1 b2 1 b3 (MSB first: each symbol starts with a transition, and a 1 has a
             second one);
     page 1  hi_expand[x]: the same for bits 4..7;
     page 2  parity[x];
     page 3  192 channel-status code bytes (T1's table).
   960 of the 1,024 bytes. The running parity of a subframe lives in the programme counter (code
   duplicated per parity state), and a byte needed twice is parked in the thread's own inbox
   (SEND, later RECV), because LDB overwrites the accumulator.

   16-bit audio in the 20-bit field: slots 4..11 are zero (aux and the four LSBs), so their two
   bytes are the constant 0xAA; V = U = 0. Parity P = parity(sample) XOR C. *)

open Asm

let pre_b = Iec60958.pre_byte Iec60958.B
let pre_m = Iec60958.pre_byte Iec60958.M
let pre_w = Iec60958.pre_byte Iec60958.W

let expand4 n = (* bits n0..n3 -> 1 n0 1 n1 1 n2 1 n3, MSB first *)
  0xAA lor (((n lsr 0) land 1) lsl 6) lor (((n lsr 1) land 1) lsl 4) lor (((n lsr 2) land 1) lsl 2) lor ((n lsr 3) land 1)

let vucp ~c ~p = 0xAA lor ((c land 1) lsl 2) lor (p land 1)

(* the CS code table: [csl], [csr] are the 192-bit blocks *)
let cs_codes (csl : int array) (csr : int array) =
  Array.init 192 (fun f -> csl.(f) lor (csr.(f) lsl 1) lor (if f = 0 then 0x80 else 0))

let bank_image ~csl ~csr =
  let b = Array.make Isa2.bank_len 0 in
  for x = 0 to 255 do
    b.(x) <- expand4 (x land 15); b.(256 + x) <- expand4 (x lsr 4); b.(512 + x) <- Iec60958.parity_of x
  done;
  Array.iteri (fun f v -> b.(768 + f) <- v) (cs_codes csl csr);
  b

(* one sample byte from in-port 0, in parity state [p]; continues at [k p'] *)
let sample_byte ~tag ~p ~k =
  let n s = Printf.sprintf "%s_p%d_%s" tag p s in
  [ L (n "in"); recv_w 4; send_w 2;
    i (Isa2.bank 0); i Isa2.ldb; send_w 4;
    recv_w 2; send_w 2; i (Isa2.bank 1); i Isa2.ldb; send_w 4;
    recv_w 2; i (Isa2.bank 2); i Isa2.ldb; waitc_else (Isa2.c_acc 0) (k p); jmp (k (1 - p)) ]

(* both bytes of a sample, starting in parity 0, ending at [fin p] *)
let sample ~tag ~fin =
  sample_byte ~tag:(tag ^ "_lo") ~p:0 ~k:(fun p -> Printf.sprintf "%s_hi_p%d_in" tag p)
  @ sample_byte ~tag:(tag ^ "_hi") ~p:0 ~k:fin
  @ sample_byte ~tag:(tag ^ "_hi") ~p:1 ~k:fin

(* the subframe tail: V U C P, with C = bit [cbit] of the stashed code byte *)
let tail ~tag ~p ~cbit ~keep ~next =
  let n s = Printf.sprintf "%s_p%d_%s" tag p s in
  [ L (n "in"); recv_w 1 ] @ (if keep then [ send_w 1 ] else [])
  @ [ waitc_else (Isa2.c_acc cbit) (n "c0");
      lda (vucp ~c:1 ~p:(1 - p)); jmp (n "out");
      L (n "c0"); lda (vucp ~c:0 ~p);
      L (n "out"); send_w 4; jmp next ]

let t0_program =
  let fin tag p = Printf.sprintf "%s_p%d_in" tag p in
  [ L "top"; recv_w 0; send_w 1;
    waitc_else 7 "pre_m"; lda pre_b; jmp "pre";
    L "pre_m"; lda pre_m;
    L "pre"; send_w 4;
    lda 0; send_w 5; send_w 5;                    (* feed word: step the synthesiser *)
    lda 0xAA; send_w 4; send_w 4 ]
  @ sample ~tag:"sl" ~fin:(fin "tl")
  @ tail ~tag:"tl" ~p:0 ~cbit:0 ~keep:true ~next:"right"
  @ tail ~tag:"tl" ~p:1 ~cbit:0 ~keep:true ~next:"right"
  @ [ L "right"; lda pre_w; send_w 4; lda 0xAA; send_w 4; send_w 4 ]
  @ sample ~tag:"sr" ~fin:(fin "tr")
  @ tail ~tag:"tr" ~p:0 ~cbit:1 ~keep:false ~next:"top"
  @ tail ~tag:"tr" ~p:1 ~cbit:1 ~keep:false ~next:"top"

let t1_program =
  [ L "t1"; lda 0; i (Isa2.bank 3); i (Isa2.ldc 192);
    L "loop"; i Isa2.ldb; send_w 0; i (Isa2.shi ~pin:7 ~msb:1 ()); jnz "loop"; jmp "t1" ]

(* ---- harness ---- *)

type source = {
  next_frame : unit -> int * int;    (* (left, right) 16-bit samples, on each feed word *)
}

let samples_source (f : int -> int * int) =
  let i = ref 0 in
  { next_frame = (fun () -> let s = f !i in incr i; s) }

type result = {
  nibbles : Bytes.t;                   (* per clock, the pin's four quarter levels *)
  bounds : (int * int * int) array;    (* (clock, quarter, transition bit) per UI boundary *)
  underruns : int;
  frames_sourced : int;
  clocks : int;
  words_t0 : int; words_t1 : int;
  enable_clock : int;
}

let store () =
  let w0, _ = assemble ~origin:0 t0_program in
  let w1, _ = assemble ~origin:0 t1_program in
  let mem = Array.make Isa2.store_len 0 in
  Array.blit w0 0 mem 0 (Array.length w0);
  Array.blit w1 0 mem 256 (Array.length w1);
  (mem, Array.length w0, Array.length w1)

(* Run the transmitter for [clocks] clocks. [bank_fault] plants a table error (controls). *)
let run ?(bank_fault = fun (_ : int array) -> ()) ?(use_rtl = false) ~csl ~csr ~inc ~(src : source) ~clocks () =
  let mem, n0, n1 = store () in
  let bank = bank_image ~csl ~csr in
  bank_fault bank;
  (* T0 page 0, T1 page 1; threads 2 and 3 idle on a self-jump in page 2 *)
  mem.(512) <- Isa2.jmp 0;
  let st = Isa2.init ~boot:[| (0, 0); (1, 0); (2, 0); (2, 0) |] ~bank () in
  let pacer = Pacer.create () in
  let rtl =
    if use_rtl then begin
      let sim = Hardcaml.Cyclesim.create (Pacer.circuit ()) in
      Hardcaml.Cyclesim.reset sim;
      Some sim
    end else None in
  let inq = Queue.create () in
  let feed = ref 0 and frames = ref 0 in
  let nib = Bytes.make clocks '\000' in
  let bounds = ref [] in
  let enable_at = ref (-1) in
  let prev_level = ref 0 in
  let mism = ref 0 in
  for c = 0 to clocks - 1 do
    let io = Isa2.io ~port_out_ready:[| Pacer.ready pacer; true; false; false |]
        ~port_in:[| (if Queue.is_empty inq then 0 else Queue.peek inq); 0; 0; 0 |]
        ~port_in_valid:[| not (Queue.is_empty inq); false; false; false |] 0 in
    let e = Isa2.step st ~mem io in
    (match e.port_pop with Some 0 -> ignore (Queue.pop inq) | _ -> ());
    let push = match e.port_push with Some (0, b) -> Some b | _ -> None in
    (match e.port_push with
     | Some (1, _) ->
       incr feed;
       if !feed mod 2 = 0 then begin
         let l, r = src.next_frame () in incr frames;
         List.iter (fun b -> Queue.push b inq) [ l land 0xff; (l lsr 8) land 0xff; r land 0xff; (r lsr 8) land 0xff ]
       end
     | _ -> ());
    let enable = !enable_at < 0 && Queue.length pacer.fifo >= Pacer.depth in
    if enable then enable_at := c;
    (match rtl with
     | Some sim ->
       let ip n v w = Hardcaml.Cyclesim.in_port sim n := Hardcaml.Bits.of_int ~width:w v in
       ip "inc" inc 32; ip "enable" (if enable then 1 else 0) 1;
       ip "push" (if push <> None then 1 else 0) 1; ip "push_data" (Option.value push ~default:0) 8;
       let rdy = Hardcaml.Bits.to_int !(Hardcaml.Cyclesim.out_port sim "ready") in
       if c > 0 && (rdy = 1) <> Pacer.ready pacer then (incr mism; Printf.eprintf "ready mismatch at %d\n" c);
       Hardcaml.Cyclesim.cycle sim
     | None -> ());
    let o = Pacer.step pacer ~inc ~enable ~push in
    (match rtl with
     | Some sim when c > 0 ->
       (* the RTL registers its outputs: after this cycle they describe this clock *)
       let n = Hardcaml.Bits.to_int !(Hardcaml.Cyclesim.out_port sim "nibble") in
       if n <> o.nibble then (incr mism; Printf.eprintf "nibble mismatch at %d: rtl %x model %x\n" c n o.nibble)
     | _ -> ());
    Bytes.set nib c (Char.chr o.nibble);
    (match o.boundary with
     | Some q ->
       let before = if q = 0 then !prev_level else (o.nibble lsr (q - 1)) land 1 in
       let after = (o.nibble lsr q) land 1 in
       bounds := (c, q, before lxor after) :: !bounds
     | None -> ());
    prev_level := (o.nibble lsr 3) land 1
  done;
  if !mism > 0 then failwith (Printf.sprintf "pacer RTL and model disagree on %d clocks" !mism);
  { nibbles = nib; bounds = Array.of_list (List.rev !bounds); underruns = pacer.underruns; frames_sourced = !frames;
    clocks; words_t0 = n0; words_t1 = n1; enable_clock = !enable_at }
