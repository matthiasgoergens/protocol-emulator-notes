(* Lockstep differential test: interpreter (isa2.ml) against RTL (sequencer2.ml) on random
   programmes and random inputs, comparing every clock the effects of that clock (host byte and tag,
   host ready, port push and pop, bank write, FINE output) and ALL architectural state (pc, page,
   acc, cnt, dl, bp, fine, armed, cfg, lsend of every thread; inbox bytes and full bits; pins,
   output enables, the quarter-clock view, the round latch, the thread counter).

   Two programme generators:
   - biased: instructions drawn with weights that favour the new ones (MBX, WAITC, EXT, SHO's
     pair / psel / cap), deadlines mostly 0 so that waits branch, fail and jump addresses anywhere;
   - uniform: every word uniformly random, the base prototype's generator.
   Planted-bug controls: every bug in Sequencer2.bugs must be caught by the biased generator. The
   uniform generator is run on the same bugs to show what it would have missed. *)

let rand_bool p = Random.float 1.0 < p

let biased_word () =
  let open Isa2 in
  let r = Random.int 100 in
  let pin () = Random.int 8 and b () = Random.int 2 and a () = Random.int 256 in
  if r < 14 then
    sho ~od:(if rand_bool 0.2 then 1 else 0) ~pair:(b ()) ~psel:(b ()) ~cap:(b ()) ~q:(Random.int 4) ~pin:(pin ()) ~msb:(b ()) ()
  else if r < 28 then (if rand_bool 0.5 then send else recv) ~ch:(Random.int 8) ~fail:(a ())
  else if r < 40 then waitc ~cond:(Random.int 16) ~fail:(a ())
  else if r < 58 then ext (if rand_bool 0.9 then Random.int 8 else 8 + Random.int 8)
      (if rand_bool 0.5 then Random.int 4 else Random.int 256)
  else if r < 63 then (if rand_bool 0.5 then out ~tag:(Random.int 8) () else outi ~tag:(Random.int 8) (Random.int 256))
  else if r < 72 then ldd (if rand_bool 0.7 then 0 else Random.int 8)
  else if r < 77 then lda (if rand_bool 0.5 then Random.int 4 else Random.int 256)
  else if r < 80 then ldc (Random.int 16)
  else if r < 84 then setp ~q:(Random.int 4) ~mask:(Random.int 256) ~value:(b ()) ~oe:(b ()) ()
  else if r < 87 then shi ~quad:(b ()) ~pin:(pin ()) ~msb:(b ()) ()
  else if r < 90 then jmp (a ())
  else if r < 92 then jnz (a ())
  else if r < 95 then waitp ~pin:(pin ()) ~value:(b ()) ~fail:(a ())
  else if r < 96 then waitd
  else if r < 97 then in_
  else if r < 98 then nop
  else Random.int 0x10000

let uniform_word () = Random.int 0x10000

let random_io () =
  Isa2.io ~pin_in4:((Random.bits () lor (Random.bits () lsl 30)) land 0xFFFFFFFF)
    ~host_in:(Random.int 256) ~host_in_valid:(Random.bool ())
    ~port_in:(Array.init 4 (fun _ -> Random.int 256)) ~port_in_valid:(Array.init 4 (fun _ -> Random.bool ()))
    ~port_out_ready:(Array.init 4 (fun _ -> Random.bool ())) ~flags:(Random.int 0x10000)
    ?host_ctl:(if rand_bool 0.004 then Some (Random.int 4, Random.int 4, Random.int 256) else None)
    (Random.int 256)

let diff_state (a : Isa2.state) (b : Isa2.state) =
  let d = ref [] in
  let arr n x y = if x <> y then d := n :: !d in
  arr "pc" a.pcs b.pcs; arr "page" a.pages b.pages; arr "acc" a.accs b.accs; arr "cnt" a.cnts b.cnts;
  arr "dl" a.dls b.dls; arr "bp" a.bps b.bps; arr "fine" a.fines b.fines; arr "armed" a.armed b.armed;
  arr "cfg" a.cfgs b.cfgs; arr "lsend" a.lsend b.lsend; arr "inbox" a.inbox b.inbox; arr "full" a.full b.full;
  if a.pin_out <> b.pin_out then d := "pin_out" :: !d;
  if a.pin_oe <> b.pin_oe then d := "pin_oe" :: !d;
  if a.pin_sub <> b.pin_sub then d := "pin_sub" :: !d;
  if a.thread <> b.thread then d := "thread" :: !d;
  if a.latch <> b.latch then d := "latch" :: !d;
  if a.bankmem <> b.bankmem then d := "bank" :: !d;
  !d

let diff_effects (e : Isa2.effects) (o : Harness2.observed) (st : Isa2.state) =
  let d = ref [] in
  if e.host_out <> o.host_out then d := "host_out" :: !d;
  if e.host_in_ready <> o.host_in_ready then d := "host_in_ready" :: !d;
  if e.port_pop <> o.port_pop then d := "port_pop" :: !d;
  if e.port_push <> o.port_push then d := "port_push" :: !d;
  if e.bank_write <> o.bank_write then d := "bank_write" :: !d;
  if e.fine_out <> o.fine_out then d := "fine_out" :: !d;
  let cfg_model = Array.fold_left (fun (acc, i) c -> (acc lor (c lsl (8 * i)), i + 1)) (0, 0) st.cfgs |> fst in
  if cfg_model <> o.cfg_out then d := "cfg_out" :: !d;
  !d

(* one programme: returns (mismatching clocks, first mismatch description) *)
let run ?bug ?(stop_at_first = false) ~gen ~seed ~cycles () =
  Random.init seed;
  let mem = Array.init Isa2.store_len (fun _ -> gen ()) in
  let boot = Array.init Isa2.n_threads (fun t ->
      if rand_bool 0.5 then (t, 0) else (Random.int 4, Random.int 256)) in
  let bank = Array.init Isa2.bank_len (fun _ -> Random.int 256) in
  let st = Isa2.init ~boot ~bank () in
  let s = Harness2.make ?bug ~boot ~bank mem in
  let bad = ref 0 and first = ref None in
  let trace = Sys.getenv_opt "LOCKSTEP_TRACE" <> None and hist = Queue.create () in
  (try
     for c = 0 to cycles - 1 do
       let io = random_io () in
       let t = st.thread in
       let w = Isa2.fetch st ~mem t in
       let before = if trace then Some (Isa2.copy st) else None in
       let e = Isa2.step st ~mem io in
       let o = Harness2.cycle s io in
       let rs = Harness2.state s o in
       let d = diff_effects e o st @ diff_state st rs in
       if trace then begin
         let b = Option.get before in
         let line = Printf.sprintf "c%d t%d pc%d %-28s acc %02x->%02x rtl %s bp %d cnt %d dl %d" c t b.pcs.(t) (Isa2.disasm w)
             b.accs.(t) st.accs.(t) (String.concat "," (Array.to_list (Array.map (Printf.sprintf "%02x") rs.accs)))
             b.bps.(t) b.cnts.(t) b.dls.(t) in
         Queue.push line hist; if Queue.length hist > 12 then ignore (Queue.pop hist);
         if d <> [] && !first = None then Queue.iter print_endline hist
       end;
       if d <> [] then begin
         incr bad;
         if !first = None then first := Some (c, String.concat "," d);
         if stop_at_first then raise Exit
       end
     done
   with Exit -> ());
  !bad, !first

(* how often each new feature was exercised, measured on the interpreter for the biased generator *)
let coverage ~seeds ~cycles =
  let counts = Hashtbl.create 32 in
  let bump k = Hashtbl.replace counts k (1 + Option.value ~default:0 (Hashtbl.find_opt counts k)) in
  for seed = 1 to seeds do
    Random.init seed;
    let mem = Array.init Isa2.store_len (fun _ -> biased_word ()) in
    let st = Isa2.init () in
    for _ = 1 to cycles do
      let io = random_io () in
      let w = Isa2.fetch st ~mem st.thread in
      let t = st.thread in
      let pc0 = st.pcs.(t) and dl0 = st.dls.(t) in
      let e = Isa2.step st ~mem io in
      let opc = (w lsr 12) land 15 in
      let moved = st.pcs.(t) <> pc0 in
      (match opc with
       | 13 ->
         let k = Printf.sprintf "mbx %s %s" (if (w lsr 11) land 1 = 1 then "recv" else "send")
             (if (w lsr 10) land 1 = 1 then "port" else "inbox") in
         bump (k ^ (if st.pcs.(t) = (pc0 + 1) land 0xFF then " done"
                    else if dl0 = 0 && moved then " fail-branch" else " stay"))
       | 14 -> bump (Printf.sprintf "waitc %02d %s" ((w lsr 8) land 15)
                       (if st.pcs.(t) = (pc0 + 1) land 0xFF then "holds" else if moved then "branch" else "stay"))
       | 15 -> bump (Printf.sprintf "ext %s" (Isa2.disasm w |> String.split_on_char ' ' |> List.hd))
       | 7 -> bump (Printf.sprintf "sho pair=%d psel=%d cap=%d" ((w lsr 6) land 1) ((w lsr 5) land 1) ((w lsr 4) land 1))
       | 11 -> bump (if (w lsr 11) land 1 = 1 then "out imm" else "out acc")
       | _ -> ());
      if e.fine_out <> None then bump "fine carried by a pin write"
    done
  done;
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) counts [] |> List.sort compare

let () =
  let runs = int_of_string (try Sys.argv.(1) with _ -> "300") in
  let only_clean = Array.length Sys.argv > 4 in
  let cycles = int_of_string (try Sys.argv.(2) with _ -> "3000") in
  let total = ref 0 in
  List.iter (fun (name, gen) ->
      let bad = ref 0 in
      let first_seed = int_of_string (try Sys.argv.(3) with _ -> "1") in
      for seed = first_seed to first_seed + runs - 1 do
        let b, first = run ~gen ~seed ~cycles () in
        bad := !bad + b;
        match first with
        | Some (c, d) when !bad = b && b > 0 -> Printf.printf "  %s seed %d: first mismatch at clock %d (%s)\n" name seed c d
        | _ -> ()
      done;
      total := !total + !bad;
      Printf.printf "lockstep %-8s %d programmes x %d clocks: %d mismatching clocks\n%!" name runs cycles !bad)
    [ ("biased", biased_word); ("uniform", uniform_word) ];
  if only_clean then exit (if !total = 0 then 0 else 1);
  print_endline "coverage of the biased generator (interpreter, 20 programmes x 3000 clocks):";
  List.iter (fun (k, v) -> Printf.printf "  %-32s %7d\n" k v) (coverage ~seeds:20 ~cycles:3000);
  (* planted bugs *)
  let seeds = 30 and ccycles = 3000 in
  Printf.printf "planted bugs (%d programmes x up to %d clocks each; seeds that caught it):\n" seeds ccycles;
  let missed = ref 0 in
  List.iter (fun (bug, desc) ->
      let caught gen =
        let n = ref 0 and first = ref None in
        for seed = 1001 to 1000 + seeds do
          let b, f = run ~bug ~stop_at_first:true ~gen ~seed ~cycles:ccycles () in
          if b > 0 then (incr n; if !first = None then first := Option.map (fun (c, d) -> (seed, c, d)) f)
        done; !n, !first in
      let nb, fb = caught biased_word and nu, _ = caught uniform_word in
      if nb = 0 then incr missed;
      Printf.printf "  %-48s biased %2d/%d  uniform %2d/%d  %s%s\n%!" desc nb seeds nu seeds
        (if nb > 0 then "caught" else "MISSED")
        (match fb with Some (sd, c, d) -> Printf.sprintf "  (seed %d clock %d: %s)" sd c d | None -> ""))
    Sequencer2.bugs;
  let ok = !total = 0 && !missed = 0 in
  print_endline (if ok then "ALL PASS" else "FAILURES");
  exit (if ok then 0 else 1)
