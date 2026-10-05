(* The one-bit DAC on the PE array: CIFB sigma-delta configurations, a fast bit-exact model of
   them, the host-link pump thread (ISA v2) and the glue that runs pump + array together.

   Chip clock 60 MHz. Each channel is one 8-PE run: left = segments 0+1+2 joined (PE 0-7, feed
   on segment 0), right = segment 3 (PE 8-15). The feed repeats its word every [period] = 10
   clocks (E2), so the modulator steps at 6 MHz; one host sample lasts 1360 clocks = 136 steps
   (44,117.6 Hz, 400 ppm above 44.1 kHz). The lane of the run's end loops to its start (E1) and
   carries the output bit y; inter-stage gains are 2^-m through the A shift (X1).

   One modulator step, y from the previous step (g = 1 means y = -1):
     FB_k : P <- sat((A >>> m_k) + (g ? a_k : -a_k))     (K = -a_k, Y negated when g)
     I_k  : S <- sat(S + A); P <- S                       (non-delaying integrator)
     last I_k also: L <- S'[15] (next y), F <- g (the pin bit)
   Pass-through PEs (P <- A, lane passed) fill the run when the order is below 4. *)
open Spec

let clock_hz = 60_000_000
let period = 10                       (* clocks per modulator step *)
let sample_clocks = 1360              (* clocks per host sample at 44.1 kHz *)

type design = { name : string; a : int array; m : int array }

(* From analysis/design.py (results/design.txt): NTF (1-z^-1)^N / D(z), Butterworth poles,
   max |NTF| = hinf; non-delaying CIFB; states scaled by powers of two to a common peak. *)
let designs =
  [ { name = "o2"; a = [| 15689; 7845 |]; m = [| 0; 1 |] };
    { name = "o3"; a = [| 11094; 8949; 9976 |]; m = [| 0; 2; 1 |] };
    { name = "o4"; a = [| 6597; 7523; 9624; 15924 |]; m = [| 0; 3; 2; 1 |] } ]

let design_of name = List.find (fun d -> d.name = name) designs

(* ---- PE configurations ---- *)
let pass = { nop with stream = true; pwb = 0; lout = 0 }
let fb ~shift ~a = { nop with stream = true; xsel = 1; ashr = shift; ysel = 0; ymod = 2; gsel = 2; alu = 0; swb = 0; pwb = 1; lout = 0; k = (-a) land 0xffff }
let integ ~last = { nop with stream = true; xsel = 0; ysel = 1; alu = 0; swb = 1; pwb = 1; gsel = 2; lout = (if last then 1 else 0); fwb = (if last then 1 else 0) }

(* the 8 ops of one run, PE order; [shift0] is the input shift of FB_1 *)
let run_ops ?(shift0 = 0) d =
  let n = Array.length d.a in
  let core =
    List.concat
      (List.init n (fun k -> [ fb ~shift:(if k = 0 then shift0 else d.m.(k)) ~a:d.a.(k); integ ~last:(k = n - 1) ]))
  in
  Array.of_list (List.init (8 - (2 * n)) (fun _ -> pass) @ core)

(* ---- fast bit-exact model of one run ---- *)
let sat v = if v > 32767 then 32767 else if v < -32768 then -32768 else v
let signed16 v = let v = v land 0xffff in if v >= 0x8000 then v - 0x10000 else v

type fast = { d : design; shift0 : int; s : int array; mutable g : bool }

let fast_create ?(shift0 = 0) d = { d; shift0; s = Array.make (Array.length d.a) 0; g = false }

(* one modulator step with input word w (16 bits); returns the pin bit (F: 1 = y negative) *)
let fast_step f w =
  let out = f.g in
  let n = Array.length f.d.a in
  for k = 0 to n - 1 do
    let x = if k = 0 then signed16 w asr f.shift0 else f.s.(k - 1) asr f.d.m.(k) in
    let a = f.d.a.(k) in
    let t = sat (x + if f.g then a else -a) in
    f.s.(k) <- sat (f.s.(k) + t)
  done;
  f.g <- f.s.(n - 1) < 0;
  out

(* ---- the pump thread (ISA v2), thread 0 ----
   Every 340 slots (1360 clocks): for each of the 4 bytes of a frame (L lo, L hi, R lo, R hi):
   at dl = 0, WAITC host_in_valid is a one-slot branch; IN; SEND to port 4 (left) or 5
   (right). The port glue sends a port's first byte as the feed's low byte and its second as
   the high byte, which commits the word (E2). If a byte is missing (underrun), U_k reports it
   (OUT tag 1, imm k), waits for the next sample instant, and retries byte k at exactly the
   slot it would have had: a frame is delayed, never torn or dropped. *)
module A = Isa2

(* threads 1-3 are parked here (HALT = JMP self); the DAC needs only thread 0 *)
let idle_pc = 200

let pump_programme () =
  (* addresses: B_k = 1 + 3k; LDD at 13; JMP at 14; U_k at 15 + 4k *)
  let b k = 1 + (3 * k) and u k = 15 + (4 * k) in
  let body =
    [ A.waitd ]
    @ List.concat
        (List.init 4 (fun k ->
             let ch = if k < 2 then 4 else 5 in
             [ A.waitc ~cond:A.c_host ~fail:(u k); A.in_; A.send ~ch ~fail:(b k + 3) ]))
    @ [ A.ldd 326; A.jmp 0 ]
  in
  let under = List.concat (List.init 4 (fun k -> [ A.outi ~tag:1 k; A.ldd 335; A.waitd; A.jmp (b k) ])) in
  let prog = body @ under in
  assert (List.length body = 15);
  let mem = Array.make A.store_len (A.jmp 0) in
  List.iteri (fun i w -> mem.(i) <- w) prog;
  mem.(idle_pc) <- A.jmp idle_pc;
  mem

(* ---- the host link: a byte FIFO the host keeps filled ---- *)
type host = {
  fifo : int Queue.t;
  depth : int;
  mutable next : int;            (* index of the next byte the host would send *)
  bytes : int array;             (* the whole stream, frame after frame *)
  mutable link_busy : int;       (* clocks until the link can carry the next byte *)
  pause : int -> bool;           (* host stalls at this clock (underrun experiments) *)
}

(* 4-bit link at 15 MHz: one byte per 8 clocks at 60 MHz *)
let link_clocks_per_byte = 8

let host_tick h clk =
  if h.link_busy > 0 then h.link_busy <- h.link_busy - 1
  else if (not (h.pause clk)) && h.next < Array.length h.bytes && Queue.length h.fifo < h.depth then begin
    Queue.push h.bytes.(h.next) h.fifo;
    h.next <- h.next + 1;
    h.link_busy <- link_clocks_per_byte - 1
  end

(* frame bytes from stereo words: L lo, L hi, R lo, R hi *)
let frame_bytes (l : int array) (r : int array) =
  let n = Array.length l in
  Array.init (4 * n) (fun i ->
      let w = (if i land 2 = 0 then l else r).(i / 4) land 0xffff in
      if i land 1 = 0 then w land 0xff else w lsr 8)

(* ---- the whole system on a simulator (Model or Rtlsim) ---- *)
module System (S : SIM) = struct
  type t = {
    arr : S.t;
    mutable seq : A.state;
    mem : int array;
    host : host;
    mutable clk : int;
    port_hi : bool array;               (* glue: next byte of port p is the high byte *)
    mutable pend : inputs;              (* glue register: the mailbox write for the next clock *)
    mutable inputs_log : inputs list;   (* every clock's array inputs, for lockstep replay *)
    log_inputs : bool;
    mutable commits : (int * int * int) list;   (* (clock, segment, word) of high-byte writes *)
    mutable underruns : (int * int) list;       (* (clock, byte index) *)
  }

  let setup_inputs ~ops_l ~ops_r =
    let l = ref [] in
    let push i = l := i :: !l in
    let ctrl sg v = push { idle with mbx_wr = true; mbx_seg = sg; mbx_sel = 2; mbx_byte = v } in
    (* configuration chains: ops of segment sg, last PE first, byte 7 first *)
    let ops = Array.append ops_l ops_r in
    for sg = 0 to 3 do
      for i = seg_end.(sg) downto seg_start.(sg) do
        let b = bytes_of_op ops.(i) in
        for j = 7 downto 0 do push { idle with cfg_wr = true; cfg_seg = sg; cfg_byte = b.(j) } done
      done
    done;
    (* left: segment 0 fed, lane loop; 1 and 2 joined; right: segment 3 fed, lane loop; all run *)
    ctrl 0 (2 lor 16 lor 64); ctrl 1 16; ctrl 2 16; ctrl 3 (2 lor 16 lor 64);
    push { idle with mbx_wr = true; mbx_seg = 0; mbx_sel = 3; mbx_byte = period };
    push { idle with mbx_wr = true; mbx_seg = 3; mbx_sel = 3; mbx_byte = period };
    List.rev !l

  let create ?(log_inputs = false) ?(depth = 16) ?(pause = fun _ -> false) ~ops_l ~ops_r ~bytes () =
    let arr = S.create () in
    let t =
      { arr; seq = A.init ~boot:[| (0, 0); (0, idle_pc); (0, idle_pc); (0, idle_pc) |] (); mem = pump_programme ();
        host = { fifo = Queue.create (); depth; next = 0; bytes; link_busy = 0; pause };
        clk = 0; port_hi = [| false; false |]; pend = idle; inputs_log = []; log_inputs;
        commits = []; underruns = [] }
    in
    List.iter (fun i -> S.cycle arr i; if log_inputs then t.inputs_log <- i :: t.inputs_log) (setup_inputs ~ops_l ~ops_r);
    t

  (* one clock: host link, sequencer slot, array; returns the two pin bits after the clock *)
  let cycle t =
    host_tick t.host t.clk;
    let hv = not (Queue.is_empty t.host.fifo) in
    let io =
      A.io ~host_in:(if hv then Queue.peek t.host.fifo else 0) ~host_in_valid:hv
        ~port_out_ready:[| true; true; true; true |] 0
    in
    let e = A.step t.seq ~mem:t.mem io in
    if e.A.host_in_ready then ignore (Queue.pop t.host.fifo);
    (match e.A.host_out with Some (1, k) -> t.underruns <- (t.clk, k) :: t.underruns | _ -> ());
    let inp = t.pend in
    S.cycle t.arr inp;
    if t.log_inputs then t.inputs_log <- inp :: t.inputs_log;
    let st = S.state t.arr in
    if inp.mbx_wr && inp.mbx_sel = 1 then t.commits <- (t.clk, inp.mbx_seg, st.segs.(inp.mbx_seg).fw) :: t.commits;
    t.pend <-
      (match e.A.port_push with
       | Some (p, byte) when p < 2 ->
         let hi = t.port_hi.(p) in
         t.port_hi.(p) <- not hi;
         { idle with mbx_wr = true; mbx_seg = (if p = 0 then 0 else 3); mbx_sel = (if hi then 1 else 0); mbx_byte = byte }
       | _ -> idle);
    t.clk <- t.clk + 1;
    st
end

(* ---- input files: raw int16 LE, stereo interleaved ---- *)
let read_stereo path =
  let ic = open_in_bin path in
  let n = in_channel_length ic / 4 in
  let b = really_input_string ic (n * 4) in
  close_in ic;
  let w i = let v = Char.code b.[i] lor (Char.code b.[i + 1] lsl 8) in if v >= 0x8000 then v - 0x10000 else v in
  (Array.init n (fun i -> w (4 * i)), Array.init n (fun i -> w ((4 * i) + 2)))

(* packed bits, MSB first *)
let write_bits path (bits : bool array) =
  let oc = open_out_bin path in
  let n = Array.length bits in
  let byte = ref 0 in
  Array.iteri
    (fun i b ->
      byte := (!byte lsl 1) lor (if b then 1 else 0);
      if i land 7 = 7 then (output_byte oc !byte; byte := 0))
    bits;
  if n land 7 <> 0 then output_byte oc (!byte lsl (8 - (n land 7)));
  close_out oc

(* the fast model over a whole input: each word held for [steps] modulator steps (ZOH) *)
let render ?(shift0 = 0) d (x : int array) ~steps =
  let f = fast_create ~shift0 d in
  let out = Array.make (Array.length x * steps) false in
  Array.iteri (fun i w -> for j = 0 to steps - 1 do out.((i * steps) + j) <- fast_step f (w land 0xffff) done) x;
  out
