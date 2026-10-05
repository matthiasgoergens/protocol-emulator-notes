(* NCO-paced serialiser: the transmit end of S/PDIF on the generic pin stage.

   Three generic pieces in a row, nothing S/PDIF-specific:
     byte FIFO (the streamer's FIFO, filled by a thread through MBX SEND on an out-port)
       -> shift register, MSB first
       -> line coder in NRZI mode (toggle on a 1)
       -> pin NCO in "pace" mode: each wrap of the phase accumulator pops one bit, and the new
          level starts at the quarter of the clock in which the wrap falls.

   The pin NCO of notes/architecture-v0.md section 2.2 (../multiphase/nco.ml) evaluates its
   accumulator at the four quarter points of each clock: phase_p = acc + p * (inc >> 2). Its
   square-wave mode outputs the MSB. Pace mode is the one new use: a carry between quarter p-1 and
   quarter p (for p = 0, between the previous clock's quarter 3 and this clock's quarter 0) is a
   bit boundary. The edge is therefore the ideal edge delayed to the start of the next quarter,
   exactly the quantisation of the square-wave mode, so the jitter is that of the quarter grid.
   At most one boundary per clock: inc must stay below 2^30 (a bit longer than four quarters).

   S/PDIF needs nothing else from it: the thread supplies the transitions of each UI (preambles
   included, since they are just transition patterns), the NRZI coder turns them into levels, the
   NCO times them. With an empty FIFO at a boundary the level holds (no transition) and
   [underrun] pulses; a receiver then sees a code violation.

   Model (plain integers) and RTL (Hardcaml) below; Pacer_check runs them in lockstep. *)

let depth = 4
let mask32 = 0xffff_ffff

type t = {
  mutable acc : int; mutable ph3 : int; mutable started : bool;
  fifo : int Queue.t; mutable sr : int; mutable sr_n : int; mutable level : int;
  mutable underruns : int; mutable pops : int;
}

let create () = { acc = 0; ph3 = 0; started = false; fifo = Queue.create (); sr = 0; sr_n = 0; level = 0; underruns = 0; pops = 0 }

let ready p = Queue.length p.fifo < depth

(* the next bit at a boundary; returns (bit, underrun) *)
let next_bit p =
  if p.sr_n > 0 then begin
    let b = (p.sr lsr 7) land 1 in p.sr <- (p.sr lsl 1) land 0xff; p.sr_n <- p.sr_n - 1; (b, false)
  end else if not (Queue.is_empty p.fifo) then begin
    let byte = Queue.pop p.fifo in
    p.sr <- (byte lsl 1) land 0xff; p.sr_n <- 7; ((byte lsr 7) land 1, false)
  end else (0, true)

type out = {
  nibble : int;             (* bit q = the level during quarter q of this clock *)
  boundary : int option;    (* the quarter in which a bit boundary fell, if any *)
  underrun : bool;
}

(* One clock. [push] is a byte the thread SENDs this clock (accepted only if [ready] held at the
   start of the clock); [enable] starts the NCO (it then never stops). The FIFO push lands at the
   end of the clock, so a byte pushed in the clock of a boundary that finds the FIFO empty is too
   late for it, as in the RTL. *)
let step p ~inc ~enable ~push =
  let can_push = ready p in
  let q0 = p.started && (p.acc < p.ph3) in
  let started = p.started || enable in
  let o =
    if not started then { nibble = (if p.level = 1 then 0xf else 0); boundary = None; underrun = false }
    else begin
      let inc4 = inc lsr 2 in
      let ph = Array.init 4 (fun j -> (p.acc + (j * inc4)) land mask32) in
      let bq = ref (if q0 then Some 0 else None) in
      for j = 1 to 3 do if ph.(j) < ph.(j - 1) then bq := Some j done;
      let nib = ref 0 and under = ref false in
      let lv = ref p.level in
      for q = 0 to 3 do
        if !bq = Some q then begin
          let b, u = next_bit p in
          if u then (under := true; p.underruns <- p.underruns + 1) else p.pops <- p.pops + 1;
          lv := !lv lxor b
        end;
        if !lv = 1 then nib := !nib lor (1 lsl q)
      done;
      p.level <- !lv;
      p.ph3 <- ph.(3);
      p.acc <- (p.acc + inc) land mask32;
      { nibble = !nib; boundary = !bq; underrun = !under }
    end in
  p.started <- started;
  (match push with Some b when can_push -> Queue.push (b land 0xff) p.fifo | _ -> ());
  o

(* ---- RTL ---- *)
open Hardcaml
open Signal

type rtl_out = { r_nibble : Signal.t; r_ready : Signal.t; r_underrun : Signal.t; r_boundary : Signal.t }

let create_rtl ~clock ~clear ~inc ~enable ~push ~push_data =
  let spec = Reg_spec.create ~clock ~clear () in
  let open Always in
  let acc = Variable.reg spec ~width:32 and ph3 = Variable.reg spec ~width:32 and started = Variable.reg spec ~width:1 in
  let sr = Variable.reg spec ~width:8 and sr_n = Variable.reg spec ~width:3 and level = Variable.reg spec ~width:1 in
  let fifo = Array.init depth (fun _ -> Variable.reg spec ~width:8) in
  let rd = Variable.reg spec ~width:2 and wr = Variable.reg spec ~width:2 and cnt = Variable.reg spec ~width:3 in
  let nib_r = Variable.reg spec ~width:4 and under_r = Variable.reg spec ~width:1 and bnd_r = Variable.reg spec ~width:3 in
  let can_push = cnt.value <:. depth in
  let run = started.value |: enable in
  let inc4 = srl inc 2 in
  let inc4x2 = inc4 +: inc4 in
  let ph = [| acc.value; acc.value +: inc4; acc.value +: inc4x2; acc.value +: inc4x2 +: inc4 |] in
  let q0 = started.value &: (acc.value <: ph3.value) in
  let b = Array.init 4 (fun j -> if j = 0 then q0 else ph.(j) <: ph.(j - 1)) in
  let any = run &: (b.(0) |: b.(1) |: b.(2) |: b.(3)) in
  let head = mux rd.value (Array.to_list (Array.map (fun v -> v.Variable.value) fifo)) in
  let have_sr = sr_n.value <>:. 0 and have_fifo = cnt.value <>:. 0 in
  let bit = mux2 have_sr (msb sr.value) (mux2 have_fifo (msb head) gnd) in
  let popping = any &: ~:have_sr &: have_fifo in
  let under = any &: ~:have_sr &: ~:have_fifo in
  let nlevel = level.value ^: (any &: bit) in
  (* level during quarter q: the new level from the boundary's quarter on *)
  let nib = concat_lsb (List.init 4 (fun q ->
      let from_here = List.fold_left (fun a j -> a |: b.(j)) gnd (List.init (q + 1) (fun j -> j)) in
      mux2 (run &: from_here) nlevel level.value)) in
  let bq = mux2 b.(0) (of_int ~width:3 0) (mux2 b.(1) (of_int ~width:3 1) (mux2 b.(2) (of_int ~width:3 2) (mux2 b.(3) (of_int ~width:3 3) (of_int ~width:3 4)))) in
  let pushing = push &: can_push in
  compile
    [ started <-- run
    ; nib_r <-- nib
    ; under_r <-- under
    ; bnd_r <-- mux2 any bq (of_int ~width:3 4)
    ; when_ run [ acc <-- acc.value +: inc; ph3 <-- ph.(3); level <-- nlevel ]
    ; when_ (any &: have_sr) [ sr <-- sll sr.value 1; sr_n <-- sr_n.value -:. 1 ]
    ; when_ popping [ sr <-- sll head 1; sr_n <--. 7; rd <-- rd.value +:. 1 ]
    ; when_ pushing [ wr <-- wr.value +:. 1 ]
    ; cnt <-- cnt.value +: uresize pushing 3 -: uresize popping 3
    ];
  (* FIFO storage writes *)
  Array.iteri (fun i v -> compile [ when_ (pushing &: (wr.value ==:. i)) [ v <-- push_data ] ]) fifo;
  { r_nibble = nib_r.value; r_ready = can_push; r_underrun = under_r.value; r_boundary = bnd_r.value }

let circuit () =
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let inc = input "inc" 32 and enable = input "enable" 1 and push = input "push" 1 and push_data = input "push_data" 8 in
  let o = create_rtl ~clock ~clear ~inc ~enable ~push ~push_data in
  Circuit.create_exn ~name:"nco_pacer"
    [ output "nibble" o.r_nibble; output "ready" o.r_ready; output "underrun" o.r_underrun; output "boundary" o.r_boundary ]

(* NCO increment for a bit (UI) rate at a clock *)
let inc_of ~ui_hz ~clk_hz = Int64.to_int (Int64.of_float (Float.round (ui_hz /. clk_hz *. 4294967296.)))
