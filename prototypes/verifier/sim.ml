(* The interpreter cross-check. One image runs on Isa2's executable specification ([Isa2.step],
   the semantics every other test in the repository uses) at its thread's page, with the other
   three threads halted, in an environment (Programmes.env). From the run it measures, for the
   image's thread:
   - every first issue of an instruction ("entry": not the second and later slots of a wait),
     with the concrete pc, cnt, acc, dl, slots since the last channel event and slots since the
     start: each must lie in some entry of the verifier's certificate;
   - every event (Spec), with its slot: each must match an outcome of [Kernel.transfer] from that
     certificate entry, with the measured gap and time inside the predicted intervals;
   - whether the run meets the specification (the ground truth for one run): every channel event
     accepted with its gap in the declared interval, and no state's deadline passed. *)

open Programmes

type measured = {
  entries : int;
  uncovered : string list;        (* concrete states or events the certificate does not contain *)
  meets_spec : (unit, string) result;
  events : int;
  edges : (int * int) list;       (* (slot, pins) of every write of the thread, for reports *)
}

let is_wait w = match (w lsr 12) land 15 with 5 | 6 | 12 | 13 | 14 -> true | _ -> false

let level_le (c : Spec.level) (a : Spec.level) =
  c = a || (match a, c with Spec.LH, (Spec.L | Spec.H) | Spec.LZ, (Spec.L | Spec.Z) | Spec.X, _ -> true | _ -> false)

let kind_le (c : Spec.kind) (a : Spec.kind) =
  match c, a with
  | Spec.Write { level = l; data = d }, Spec.Write { level = l'; data = d' } -> d = d' && level_le l l'
  | _ -> c = a

let ev_le c a = List.length c = List.length a && List.for_all2 (fun (p, k) (p', k') -> p = p' && kind_le k k') c a

(* the store with [img] at page [thread] and every other thread halted at pc 0 *)
let store img =
  let s = Array.make Isa2.store_len 0 in
  for t = 0 to Isa2.n_threads - 1 do
    for pc = 0 to Isa2.page_len - 1 do
      s.((t lsl Isa2.pc_bits) lor pc) <- (if t = img.thread then img.words.(pc) else if pc = 0 then Isa2.halt_at 0 else 0)
    done
  done; s

type slave = { mutable hold : int; mutable prev_scl : int; rng : Random.State.t; stretch : unit -> int }

let run ?(slots = 60_000) ?(stretch_max = 20_000) ~seed (cert : Kernel.certificate) img =
  let rng = Random.State.make [| seed |] in
  let mem = store img in
  let st = Isa2.init ~boot:(Array.init Isa2.n_threads (fun t -> (t, 0))) () in
  let t = img.thread in
  let spec = img.spec in
  let h = Kernel.index cert in
  let uncovered = ref [] and n_entries = ref 0 and n_events = ref 0 and edges = ref [] in
  let fail_spec = ref None in
  let note_spec s = if !fail_spec = None then fail_spec := Some s in
  (* after the run's first event the specification does not accept, the certificate has nothing
     to say (the analysis stops each path there too), so the cross-check stops *)
  let off_spec = ref false in
  let miss s = if not !off_spec && List.length !uncovered < 20 then uncovered := s :: !uncovered in
  (* concrete specification state *)
  let astate = ref spec.Spec.start and last_ev = ref 0 in
  (* the slave model for I2C: after each release of SCL by the master, hold it low for a random
     number of clocks: mostly none, sometimes short, now and then past the stretch limit *)
  let releases = ref 0 in
  let sl = { hold = 0; prev_scl = 1; rng;
             (* seed 1: the slave never stretches; seed 2: at most one slot; others: mixed *)
             (* seeds from 1000 are targeted: seed = 1000 + 64 n + m stretches only the n-th
                release (from 1), by 4m clocks (m = 63: for ever) *)
             stretch = (fun () -> if seed >= 1000 then begin
                 incr releases;
                 let n = (seed - 1000) / 64 and m = (seed - 1000) mod 64 in
                 if !releases <> n then 0 else if m = 63 then 1_000_000 else 4 * m end
               else if seed = 1 then 0 else if seed = 2 then Random.State.int rng 5 else
                          match Random.State.int rng 10 with
                 | 0 | 1 | 2 | 3 | 4 -> 0 | 5 | 6 | 7 -> Random.State.int rng 40
                 | 8 -> Random.State.int rng 400 | _ -> Random.State.int rng stretch_max) } in
  let pin_in_of () =
    let drv p = (st.pin_oe lsr p) land 1 = 1 and out p = (st.pin_out lsr p) land 1 in
    match img.env with
    | Pull_up -> List.fold_left (fun a p -> a lor ((if drv p then out p else 1) lsl p)) 0 [ 0; 1; 2; 3; 4; 5; 6; 7 ]
    | Random_inputs -> if seed mod 4 = 0 then 0 else Random.State.int rng 256
    | I2c_slave { sda; scl } ->
      let master_scl = if drv scl then out scl else 1 in
      if master_scl = 1 && sl.prev_scl = 0 then sl.hold <- sl.stretch ();
      sl.prev_scl <- master_scl;
      let scl_v = if sl.hold > 0 then (sl.hold <- sl.hold - 1; 0) else master_scl in
      let sda_v = if drv sda && out sda = 0 then 0 else Random.State.int rng 2 in
      let base = List.fold_left (fun a p -> a lor ((if drv p then out p else 1) lsl p)) 0 [ 0; 1; 2; 3; 6; 7 ] in
      base lor (sda_v lsl sda) lor (scl_v lsl scl) in
  let random_io pin_in =
    match img.env with
    | Random_inputs ->
      Isa2.io ~host_in:(Random.State.int rng 256) ~host_in_valid:(Random.State.int rng 8 = 0)
        ~port_in:(Array.init 4 (fun _ -> Random.State.int rng 256))
        ~port_in_valid:(Array.init 4 (fun _ -> Random.State.bool rng))
        ~port_out_ready:(Array.init 4 (fun _ -> Random.State.bool rng))
        ~flags:(Random.State.int rng 65536) pin_in
    | _ -> Isa2.io pin_in in
  (* the thread's previous issue: pc, word, dl, and whether it was a stay *)
  let prev = ref None in
  let entry_state = ref None in   (* the abstract entry of the instruction now executing *)
  let slot = ref 0 in
  let halted_for = ref 0 in
  let max_deadline = List.fold_left (fun m tr -> match tr.Spec.gap.Interval.hi with Some x -> max m x | None -> m) 0 spec.transitions in
  let clock = ref 0 in
  let stop = ref false in
  while not !stop && !slot < slots do
    let pin_in = pin_in_of () in
    let io = random_io pin_in in
    if st.thread <> t then ignore (Isa2.step st ~mem io)
    else begin
      let s = !slot in
      let pc = st.pcs.(t) and cnt = st.cnts.(t) and acc = st.accs.(t) and dl = st.dls.(t) in
      let w = mem.((t lsl Isa2.pc_bits) lor pc) in
      let continuation = match !prev with
        | Some (ppc, pw, pdl) -> ppc = pc && is_wait pw && ((pw lsr 12) land 15 = 12 || pdl <> 0)
        | None -> false in
      let since = s - !last_ev in
      (match Spec.deadline spec !astate with
       | Some d when since > d -> note_spec (Printf.sprintf "slot %d pc %d: %d slots without an event in state %s (deadline %d)"
                                               s pc since (spec.state_name !astate) d)
       | _ -> ());
      if not continuation then begin
        incr n_entries;
        (* A5's view: the thread's enables are the chip's, other threads being halted *)
        let k = { Kernel.pc; astate = !astate; cnt = Known cnt; acc = Known acc; oe_known = 0xFF; oe = st.pin_oe } in
        let v = { Kernel.dl = Interval.exactly dl; since = Interval.exactly since; time = Interval.exactly s } in
        let found = List.find_opt (fun (tk, tv) -> Kernel.key_covers ~table:tk k && Kernel.value_leq v tv)
            (try Hashtbl.find h (pc, !astate) with Not_found -> []) in
        (match found with
         | None -> miss (Printf.sprintf "slot %d: %s %s not in the certificate" s (Kernel.key_to_string k) (Kernel.value_to_string v))
         | Some _ -> ());
        entry_state := Option.map (fun e -> (e, s)) found
      end;
      (* the pins this slot sees, as Isa2 computes them (round latch, D6) *)
      let latch = if t = 0 then pin_in else st.latch in
      let seen = if (st.cfgs.(t) lsr 7) land 1 = 1 then latch else pin_in in
      ignore (Isa2.step st ~mem io);
      let next_pc = st.pcs.(t) in
      let op = (w lsr 12) land 15 in
      let lvl p = if (st.pin_oe lsr p) land 1 = 0 then Spec.Z else if (st.pin_out lsr p) land 1 = 1 then Spec.H else Spec.L in
      let pin = (w lsr 9) land 7 and b8 = (w lsr 8) land 1 in
      let ev =
        match op with
        | 1 -> let mask = (w lsr 4) land 0xFF in
          List.filter_map (fun p -> if (mask lsr p) land 1 = 1 then Some (p, Spec.Write { level = lvl p; data = false }) else None) [ 0; 1; 2; 3; 4; 5; 6; 7 ]
        | 7 -> let ps = if (w lsr 6) land 1 = 1 then [ pin; (pin + 1) land 7 ] else [ pin ] in
          List.sort compare (List.map (fun p -> (p, Spec.Write { level = lvl p; data = true })) ps)
        | 8 -> [ (pin, Spec.Sample) ]
        | 5 -> if (seen lsr pin) land 1 = b8 then [ (pin, Spec.Observe b8) ] else if dl = 0 then [ (pin, Spec.Expire b8) ] else []
        | _ -> [] in
      let mask = List.fold_left (fun m (p, k) -> match k with Spec.Write _ -> m lor (1 lsl p) | _ -> m) 0 ev in
      if mask <> 0 then edges := (s, mask) :: !edges;
      (* check the event against the certificate's prediction from this instruction's entry *)
      (if ev <> [] then match !entry_state with
          | None -> ()
          | Some ((k, v), s0) ->
            let j = s - s0 in
            let raws = Kernel.transfer w k v.Kernel.dl in
            let ok = List.exists (fun (r : Kernel.raw) ->
                ev_le ev r.ev && Interval.contains r.at j && r.next_pc = next_pc
                && Interval.contains (Interval.plus v.Kernel.time r.at) s
                && Interval.contains (Interval.plus v.Kernel.since r.at) (s - !last_ev)) raws in
            if not ok then miss (Printf.sprintf "slot %d pc %d (%s): event %s not predicted from %s %s"
                                   s pc (Isa2.disasm w) (Spec.event_to_string ev) (Kernel.key_to_string k) (Kernel.value_to_string v)));
      (* the concrete specification *)
      (match Kernel.channel_event spec ev with
       | [] -> ()
       | cev ->
         incr n_events;
         let gap = s - !last_ev in
         (match Spec.next spec !astate cev with
          | None -> off_spec := true;
            note_spec (Printf.sprintf "slot %d pc %d: event %s not accepted in state %s" s pc
                                 (Spec.event_to_string cev) (spec.state_name !astate))
          | Some tr ->
            if not (Interval.contains tr.gap gap) then
              note_spec (Printf.sprintf "slot %d pc %d: %s gap %d, declared %s" s pc tr.label gap (Interval.to_string tr.gap));
            astate := tr.dst);
         last_ev := s);
      prev := Some (pc, w, dl);
      (* halted: JMP self; run on past the longest deadline so a missed one shows *)
      if op = 9 && w land 0xFF = pc then incr halted_for else halted_for := 0;
      if !halted_for > max_deadline + 2 then stop := true;
      incr slot
    end;
    incr clock
  done;
  { entries = !n_entries; uncovered = List.rev !uncovered;
    meets_spec = (match !fail_spec with None -> Ok () | Some s -> Error s);
    events = !n_events; edges = List.rev !edges }
