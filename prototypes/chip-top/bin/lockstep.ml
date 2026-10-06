(* Lockstep of the chip core's RTL against its executable specification, every clock, on random
   programmes, random pad inputs and random host-link traffic; then the planted integration bugs,
   each of which must be caught.

     lockstep.exe run TRIALS CLOCKS [SEED]      the design
     lockstep.exe controls TRIALS CLOCKS        every planted bug
     lockstep.exe layouts TRIALS CLOCKS         the design at 4, 8 and 16 PEs

   Compared every clock: every output pad's nibble and the uio output enables (what the pins
   show); and the architectural state of the sequencer and of every PE, the host FIFOs' counts,
   the CRC register, the NCO's output register, the matcher's sum, the edge sampler's outputs
   and the host link's read buffer. *)

module S = Chip_spec

let pr = Printf.printf

open Gen

(* ---- one trial ---- *)

type trial = {
  cfg : S.config;
  clocks : int;
  seed : int;
}

let state_diffs (s : S.t) (r : Chip_sim.t) =
  let d = ref [] in
  let cmp name a b = if a <> b then d := Printf.sprintf "%s: spec %x rtl %x" name a b :: !d in
  let per name w = Array.init 4 (fun t -> (Chip_sim.get r ("seq_dbg_" ^ name) lsr (w * t)) land ((1 lsl w) - 1)) in
  let pend = Chip_sim.get r "seq_dbg_pend" in
  let st = s.seq in
  let cmp4 name w (a : int array) =
    let b = per name w in
    Array.iteri (fun t x -> if not (name = "acc" && pend land 4 <> 0 && pend land 3 = t) then cmp (Printf.sprintf "seq %s%d" name t) x b.(t)) a
  in
  cmp4 "pc" 8 st.pcs; cmp4 "page" 2 st.pages; cmp4 "acc" 8 st.accs; cmp4 "cnt" 12 st.cnts; cmp4 "dl" 12 st.dls;
  cmp4 "bp" 10 st.bps; cmp4 "fine" 8 st.fines; cmp4 "armed" 1 st.armed; cmp4 "cfg" 8 st.cfgs;
  cmp4 "lsend" 3 st.lsend; cmp4 "inbox" 8 st.inbox; cmp4 "full" 1 st.full;
  cmp "seq thread" st.thread (Chip_sim.get r "seq_dbg_thread");
  cmp "seq latch" st.latch (Chip_sim.get r "seq_dbg_latch");
  let pes = (Upe.Model.state s.pe).pes in
  Array.iteri
    (fun i (p : Upe.Spec.pe_state) ->
      cmp (Printf.sprintf "pe%d S" i) p.s (Chip_sim.get r (Printf.sprintf "pe_s%d" i));
      cmp (Printf.sprintf "pe%d P" i) p.p (Chip_sim.get r (Printf.sprintf "pe_p%d" i));
      cmp (Printf.sprintf "pe%d Pv" i) (Bool.to_int p.pv) (Chip_sim.get r (Printf.sprintf "pe_pv%d" i));
      cmp (Printf.sprintf "pe%d F" i) (Bool.to_int p.f) (Chip_sim.get r (Printf.sprintf "pe_f%d" i));
      cmp (Printf.sprintf "pe%d L" i) (Bool.to_int p.l) (Chip_sim.get r (Printf.sprintf "pe_l%d" i));
      let c = Chip_sim.get_bits r (Printf.sprintf "pe_cfg%d" i) in
      Array.iteri (fun j v -> cmp (Printf.sprintf "pe%d cfg%d" i j) v (Hardcaml.Bits.to_int (Hardcaml.Bits.select c (8 * j + 7) (8 * j)))) p.cfg)
    pes;
  Array.iteri
    (fun j (g : Upe.Spec.seg_state) ->
      let get n = Chip_sim.get r (Printf.sprintf "seg_%s%d" n j) in
      cmp (Printf.sprintf "seg%d feed low" j) g.flo (get "flo"); cmp (Printf.sprintf "seg%d feed high" j) g.fhi (get "fhi");
      cmp (Printf.sprintf "seg%d feed valid" j) (Bool.to_int g.fv) (get "fv"); cmp (Printf.sprintf "seg%d control" j) g.ctrl (get "ctrl");
      cmp (Printf.sprintf "seg%d repeat" j) g.rep (get "rep"); cmp (Printf.sprintf "seg%d repeat count" j) g.cnt (get "cnt");
      cmp (Printf.sprintf "seg%d committed word" j) g.fw (get "fw"))
    (Upe.Model.state s.pe).segs;
  cmp "send byte order" (Array.fold_left ( lor ) 0 (Array.mapi (fun p b -> Bool.to_int b lsl p) s.send_hi)) (Chip_sim.get r "send_hi");
  let holds = Chip_sim.get_bits r "holds" in
  for p = 0 to 3 do
    let h = Hardcaml.Bits.to_int (Hardcaml.Bits.select holds (18 * p + 17) (18 * p)) in
    cmp (Printf.sprintf "port %d hold state" p) s.hold_st.(p) (h land 3);
    if s.hold_st.(p) <> 0 then cmp (Printf.sprintf "port %d hold word" p) s.hold_w.(p) (h lsr 2)
  done;
  cmp "hostin count" (Queue.length s.hostin) (Chip_sim.get r "hin_count");
  (* the heads of the FIFOs every clock: with the counts, a wrong entry or order shows when it
     reaches the head *)
  (match Queue.peek_opt s.hostin with Some v -> cmp "hostin head" v (Chip_sim.get r "hin_head") | None -> ());
  (match Queue.peek_opt s.hostout with Some (tag, v) -> cmp "hostout head" ((tag lsl 8) lor v) (Chip_sim.get r "hout_head") | None -> ());
  (match Queue.peek_opt s.smp.fifo with
   | Some (w, n) -> cmp "sampler head" ((1 lsl 20) lor (n lsl 16) lor w) (Chip_sim.get r "smp_head")
   | None -> cmp "sampler empty" 0 (Chip_sim.get r "smp_head" lsr 20));
  cmp "streamer pins and full" ((Bool.to_int (Pstream.Model.full s.str) lsl 8) lor (s.str.oe lsl 4) lor s.str.out) (Chip_sim.get r "str_out");
  cmp "hostout count" (Queue.length s.hostout) (Chip_sim.get r "hout_count");
  cmp "crc" s.crc (Chip_sim.get r "crc");
  cmp "nco" s.nco_out (Chip_sim.get r "nco");
  cmp "matcher sum" (fst (S.matcher_now s)) (Chip_sim.get r "match_y");
  cmp "rbuf" s.rbuf (Chip_sim.get r "rbuf");
  let e = s.es_out in
  cmp "edge sampler" (((if e.valid then e.bit else 0) lsl 3) lor (Bool.to_int e.valid lsl 2) lor (Bool.to_int e.burst_end lsl 1) lor Bool.to_int s.es.in_burst)
    (Chip_sim.get r "es");
  cmp "edge sampler last bit" s.es_last (Chip_sim.get r "es_last");
  List.rev !d

let out_diffs (a : S.outputs) (b : S.outputs) =
  let d = ref [] in
  Array.iteri (fun i x -> if x <> b.pad_nib.(i) then d := Printf.sprintf "pad %d: spec %x rtl %x" i x b.pad_nib.(i) :: !d) a.pad_nib;
  if a.uio_oe <> b.uio_oe then d := Printf.sprintf "uio_oe: spec %02x rtl %02x" a.uio_oe b.uio_oe :: !d;
  List.rev !d

exception Mismatch of int * string list

(* Runs one trial; returns the clock of the first mismatch and the differences, or None. *)
let run_trial ?(compare_state = true) { cfg; clocks; seed } =
  let r = Random.State.make [| seed |] in
  let r_gen = r in
  let mode = modes.(seed mod Array.length modes) in
  let spec = S.create ~cfg () and rtl = Chip_sim.create ~cfg () in
  let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
  let b = Board.create () in
  let rates = pad_rates r in
  let world = ext_world r ~rates in
  setup_traffic ~mode r b.host ~cfg;
  let reset_at = if Random.State.int r 4 = 0 then Random.State.int r clocks else -1 in
  try
    for c = 0 to clocks - 1 do
      if Host.idle b.host then running_traffic ~mode r b.host;
      let smp = Board.samples b ~ext:(world b.out) in
      let reset = c < 2 || (c >= reset_at && c < reset_at + 3) in
      (* a reset in the middle of a host transaction desynchronises the link: the host starts
         again, as a real one would after resetting the chip *)
      if c = reset_at then begin
        (* the host abandons its transaction when it resets the chip, and waits until the
           synchronisers have settled before it starts again *)
        let s = b.host.s in
        b.host <- Host.create ();
        b.host.s <- s;
        Host.submit b.host (Host.Idle 16);
        setup_traffic ~mode r_gen b.host ~cfg
      end;
      (match Board.advance b cores ~smp ~reset with
       | [ a; o ] ->
         let d = out_diffs a o in
         let d = if d = [] && compare_state then state_diffs spec rtl else d in
         let d = if d = [] then d else
             d @ [ Printf.sprintf "(sampler: cfg clocked %b period %d width %d trig %d/%d offset %d frame %d; fifo %s; held %b)"
                     spec.smp.cfg.clocked spec.smp.cfg.period spec.smp.cfg.width spec.smp.cfg.trig_pin spec.smp.cfg.trig_val
                     spec.smp.cfg.offset spec.smp.cfg.frame_len
                     (String.concat "," (List.map (fun (w, n) -> Printf.sprintf "%04x/%d" w n) (List.of_seq (Queue.to_seq spec.smp.fifo))))
                     (S.held spec) ]
               @ [ (match spec.last_fetch with Some (tg, a, b) -> Printf.sprintf "(last fetch: target %d address %x byte %x)" tg a b | None -> "(no fetch yet)") ] in
         if d <> [] then raise (Mismatch (c, d))
       | _ -> assert false)
    done;
    None
  with Mismatch (c, d) -> Some (c, d)

let campaign ?(stop = true) ~cfg ~trials ~clocks ~seed0 () =
  let fails = ref [] and total = ref 0 in
  (try
     for k = 0 to trials - 1 do
       match (try run_trial { cfg; clocks; seed = seed0 + k } with e -> Some (-1, [ "exception: " ^ Printexc.to_string e ])) with
       | None -> total := !total + clocks
       | Some (c, d) ->
         total := !total + c + 1;
         fails := (seed0 + k, c, d) :: !fails;
         if stop then raise Exit
     done
   with Exit -> ());
  (!total, List.rev !fails)

let layout_name (l : Upe.Spec.layout) =
  String.concat "|" (List.init 4 (fun j -> string_of_int (l.end_.(j) - l.start.(j) + 1)))

let run_design ~cfg ~trials ~clocks ~seed0 =
  Chip_rtl.bug := "";
  let t0 = Unix.gettimeofday () in
  let total, fails = campaign ~stop:false ~cfg ~trials ~clocks ~seed0 () in
  pr "layout %s, store %d words: %d trials x %d clocks, %d clocks compared, %d trials with mismatches (%.0f s)\n"
    (layout_name cfg.layout) cfg.prog_words trials clocks total (List.length fails) (Unix.gettimeofday () -. t0);
  List.iter (fun (s, c, d) -> pr "  seed %d, clock %d:\n    %s\n" s c (String.concat "\n    " (List.filteri (fun i _ -> i < 8) d))) fails;
  let cov = List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) S.cov []) in
  pr "  coverage (events counted on the specification): %s\n"
    (String.concat ", " (List.map (fun (k, v) -> Printf.sprintf "%s %d" k v) cov));
  Hashtbl.reset S.cov;
  flush stdout;
  fails = []

let controls ~cfg ~trials ~clocks =
  let caught = ref 0 in
  List.iter
    (fun (b, what) ->
      Chip_rtl.bug := b;
      let _, fails = campaign ~cfg ~trials ~clocks ~seed0:5000 () in
      (match fails with
       | (s, c, d) :: _ ->
         incr caught;
         pr "%-20s caught: seed %d clock %5d  (%s)\n    first diff: %s\n" b s c what (List.hd d)
       | [] -> pr "%-20s MISSED in %d trials  (%s)\n" b trials what);
      flush stdout)
    Chip_rtl.bugs;
  Chip_rtl.bug := "";
  pr "%d of %d planted integration bugs caught\n" !caught (List.length Chip_rtl.bugs)

(* the design with register toggle coverage (Cov): per block, and the never-changed bits listed
   in [never_file] *)
let coverage ~cfg ~trials ~clocks ~seed0 ~never_file =
  Cov.enable ();
  Chip_sim.coverage := true;
  let ok = run_design ~cfg ~trials ~clocks ~seed0 in
  (match Chip_sim.coverage_acc ~cfg () with
   | Some acc ->
     let const, rounds = Cov.constant_bits acc.source acc.infos in
     pr "three-valued fixpoint from reset: %d rounds\n" rounds;
     Cov.report ~const ~title:(Printf.sprintf "RTL register coverage, layout %s" (layout_name cfg.layout)) acc;
     let oc = open_out never_file in
     Cov.write_never ~const oc acc;
     close_out oc;
     pr "never-changed bits listed in %s\n" never_file
   | None -> pr "no coverage recorded\n");
  ok

let () =
  let cfg = S.default_config in
  match Array.to_list Sys.argv with
  | [ _; "regmap"; sizes; prog_words; file ] ->
    (* every register of Tt_top.create as emitted (bin/emit.ml): its Verilog name, width and
       source line, for mapping a hardened netlist's flip-flops back to blocks (sim/gate_cov.py) *)
    Cov.enable ();
    let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' sizes)) in
    let cfg = { S.layout = Upe.Spec.layout_of_sizes sizes; prog_words = int_of_string prog_words } in
    let c = Tt_top.create ~cfg ~memories:`Macros ~name:"chip_tt" () in
    let _, infos = Cov.instrument c in
    let oc = open_out file in
    Array.iter (fun (i : Cov.reg) -> Printf.fprintf oc "_%d %d %s %s %s\n" i.uid i.width i.loc (Cov.block_of i.file) (if i.label = "" then "-" else i.label)) infos;
    close_out oc
  | _ :: "coverage" :: sizes :: n :: c :: s :: never_file :: profile ->
    Gen.wide := (profile = [ "wide" ]);
    let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' sizes)) in
    let cfg = { cfg with layout = Upe.Spec.layout_of_sizes sizes } in
    exit (if coverage ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:(int_of_string s) ~never_file then 0 else 1)
  | [ _; "run"; n; c ] -> exit (if run_design ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:1 then 0 else 1)
  | [ _; "run"; n; c; s; "wide" ] ->
    Gen.wide := true;
    exit (if run_design ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:(int_of_string s) then 0 else 1)
  | [ _; "controls"; n; c; "wide" ] -> Gen.wide := true; controls ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c)
  | [ _; "run"; n; c; s ] ->
    exit (if run_design ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:(int_of_string s) then 0 else 1)
  | [ _; "controls"; n; c ] -> controls ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c)
  | [ _; "layouts"; n; c ] ->
    List.iter
      (fun sizes ->
        ignore (run_design ~cfg:{ cfg with layout = Upe.Spec.layout_of_sizes sizes } ~trials:(int_of_string n)
                  ~clocks:(int_of_string c) ~seed0:100))
      [ [| 1; 1; 1; 1 |]; [| 2; 2; 2; 2 |]; [| 2; 2; 4; 8 |] ];
    ignore (run_design ~cfg:{ cfg with prog_words = 256 } ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:200)
  | _ -> prerr_endline "usage: lockstep.exe run N CLOCKS [SEED] | controls N CLOCKS | layouts N CLOCKS | coverage SIZES N CLOCKS SEED NEVER_FILE [wide]; run N CLOCKS SEED wide and controls N CLOCKS wide: the wide generator (Gen)"
