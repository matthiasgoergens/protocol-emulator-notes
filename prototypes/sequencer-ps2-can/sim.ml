(* Continuous-time simulation kernel shared by the PS/2 and CAN benches.

   Time is an integer in femtoseconds, so clocks of slightly different frequencies (oscillator
   tolerance) are exact to 1 fs per edge. Every participant is a clocked agent: the sequencer
   (interpreter and RTL in lockstep), and the independent models, which sample the wires at their
   own clocks. *)

let fs_per_s = 1_000_000_000_000_000
let us n = int_of_float (n *. 1e9)            (* microseconds to fs *)
let ns n = int_of_float (n *. 1e6)
let period_of_hz f = int_of_float (Float.round (float_of_int fs_per_s /. f))

type agent = { mutable next : int; period : int; fire : int -> unit; name : string }

let agent ?(phase = 0) ~name ~hz fire = { next = phase; period = period_of_hz hz; fire; name }

(* Run until [until] (fs) or until [stop ()] holds. Agents with equal times fire in list order. *)
let run ?(stop = fun () -> false) ~until agents =
  let now = ref 0 in
  while !now < until && not (stop ()) do
    let a = List.fold_left (fun best a -> match best with
      | None -> Some a | Some b -> if a.next < b.next then Some a else best) None agents in
    match a with
    | None -> now := until
    | Some a -> now := a.next; a.fire a.next; a.next <- a.next + a.period
  done;
  !now

(* An open-collector line with a pull-up and a finite rise time: low while any driver pulls, and
   high only once [rise] has elapsed since the last driver let go. *)
module Oc = struct
  type t = { rise : int; pulling : (string, unit) Hashtbl.t; mutable released_at : int }
  let create ~rise = { rise; pulling = Hashtbl.create 4; released_at = min_int / 2 }
  let set l ~who ~pull ~now =
    let was = Hashtbl.length l.pulling > 0 in
    if pull then Hashtbl.replace l.pulling who () else Hashtbl.remove l.pulling who;
    if was && Hashtbl.length l.pulling = 0 then l.released_at <- now
  let level l ~now = if Hashtbl.length l.pulling > 0 then 0 else if now - l.released_at >= l.rise then 1 else 0
  let pulled_by l who = Hashtbl.mem l.pulling who
end

(* A sequencer running interpreter and RTL in lockstep. Every cycle both get the same inputs, and
   pins, output enables, host output and pcs are compared. *)
module Machine = struct
  type t = {
    st : Isa_v.state; h : Harness_v.t option; mem : int array array;
    mutable cycle : int; mutable mismatches : int; mutable first : string option;
  }
  let create ?(rtl = true) mem =
    { st = Isa_v.init (); h = (if rtl then Some (Harness_v.make mem) else None); mem;
      cycle = 0; mismatches = 0; first = None }
  (* the assist state as the RTL's debug ports pack it: per thread last, run, crc *)
  let dbg_of (st : Isa_v.state) =
    List.init Isa_v.n_threads (fun t -> (st.lasts.(t) lsl 19) lor (st.runs.(t) lsl 16) lor st.crcs.(t))
  let thread m = m.st.thread   (* the thread that executes on the next step *)
  let step m ~pin_in ~host_in ~host_in_valid =
    let eff = Isa_v.step m.st ~mem:m.mem ~pin_in ~host_in ~host_in_valid in
    (match m.h with
     | None -> ()
     | Some h ->
       let o = Harness_v.cycle h ~pin_in ~host_in ~host_in_valid in
       let ok = o.pin_out = m.st.pin_out && o.pin_oe = m.st.pin_oe && o.host_out = eff.host_out
                && o.host_in_ready = eff.host_in_ready && o.pcs = Array.to_list m.st.pcs
                && o.dbg = dbg_of m.st in
       if not ok then begin
         m.mismatches <- m.mismatches + 1;
         if m.first = None then
           m.first <- Some (Printf.sprintf "cycle %d: rtl out=%02x oe=%02x pcs=%s | isa out=%02x oe=%02x pcs=%s"
                              m.cycle o.pin_out o.pin_oe (String.concat "," (List.map string_of_int o.pcs))
                              m.st.pin_out m.st.pin_oe
                              (String.concat "," (Array.to_list (Array.map string_of_int m.st.pcs))))
       end);
    m.cycle <- m.cycle + 1;
    eff
end

(* Programme assembly with symbolic labels, for the 8-bit-address variant. *)
module Asm = struct
  type item = W of int | L of string | R of string * (int -> int)
  let assemble ?(name = "programme") items =
    let labels = Hashtbl.create 32 in
    let pos = ref 0 in
    List.iter (function L l ->
      if Hashtbl.mem labels l then failwith ("duplicate label " ^ l);
      Hashtbl.replace labels l !pos | _ -> incr pos) items;
    if !pos > Isa_v.prog_len then failwith (Printf.sprintf "%s too long: %d words" name !pos);
    let prog = Array.make Isa_v.prog_len Isa_v.halt in
    let pos = ref 0 in
    let find l = match Hashtbl.find_opt labels l with Some a -> a | None -> failwith ("no label " ^ l) in
    List.iter (function
      | L _ -> ()
      | W w -> prog.(!pos) <- w; incr pos
      | R (l, f) -> prog.(!pos) <- f (find l); incr pos) items;
    prog, !pos, find
  let jmp l = R (l, Isa_v.jmp)
  let jnz l = R (l, Isa_v.jnz)
  let waitp ~pin ~value l = R (l, fun a -> Isa_v.waitp ~pin ~value ~fail:a)
  let jc ~cond l = R (l, fun a -> Isa_v.jc ~cond a)
  (* WAITP is an immediate branch only while dl = 0; after a wait that can end early (LDD n;
     WAITP), dl is still counting, so a branch must clear it first *)
  let br ~pin ~value l = [ W (Isa_v.ldd 0); waitp ~pin ~value l ]
  (* exactly n slots of delay: LDD k; WAITD takes k + 2 slots *)
  let delay n =
    if n < 0 then failwith (Printf.sprintf "negative delay %d" n)
    else if n = 0 then [] else if n = 1 then [ W Isa_v.nop ]
    else [ W (Isa_v.ldd (n - 2)); W Isa_v.waitd ]
  (* the opcodes a programme uses: to show which ISA additions a protocol needs *)
  let opcodes prog len =
    let s = Hashtbl.create 16 in
    for i = 0 to len - 1 do Hashtbl.replace s (Isa_v.op_of_code ((prog.(i) lsr 12) land 0xF)) () done;
    s
  let uses_only_base prog len =
    let ok = ref true in
    for i = 0 to len - 1 do
      let w = prog.(i) in
      match Isa_v.op_of_code ((w lsr 12) land 0xF) with
      | Isa_v.JC | CFG -> ok := false
      | SHO | SHI -> if (w lsr 4) land 7 <> 0 then ok := false
      | OUT -> if w land 0xFFF <> 0 then ok := false
      | _ -> ()
    done; !ok
end
