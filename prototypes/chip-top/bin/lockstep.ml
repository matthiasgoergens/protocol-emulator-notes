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

(* ---- hwfuzz on the chip core, with the specification as the oracle ----

   The fuzz input is a string of commands, each a code byte and its operands: host-link
   transactions (register, programme, bank, PE chain and segment writes, FIFO traffic, reads, run
   and stop, restarts) and per-pad toggle rates for the outside world. A transducer turns it into the
   core's per-clock pad samples, with the host-link timing of Host and the board's two-clock
   latency, for hwfuzz's instrumented simulation (open loop: lines the chip would drive read 0).
   Every input hwfuzz keeps is then replayed on the board with feedback, the specification and the
   RTL in lockstep, every pad and the architectural state compared every clock, and the RTL's
   register toggles recorded (Cov). The commands are hwfuzz's units, so whole commands are
   inserted, duplicated, deleted and swapped. *)
module Fz = struct
  open Regs
  type cmd = { span : int * int; act : Host.t -> float array -> unit }

  let rate_of b = [| 0.0; 0.002; 0.01; 0.05; 0.2 |].(b mod 5)

  (* The specification's contracts (README section 2), which a real host must keep and the fuzzer
     therefore keeps too: the assists' configuration (0x40-0x6F and the matcher's chain) changes
     only while they are held, so such writes are wrapped in a hold; widths are 1, 2 or 4; periods
     at least 1; the CRC mask is 2^w - 1. [legal] turns one register write into writes that keep
     them, following the register file in [shadow]. *)
  let legal shadow a v =
    let ctrl = shadow.(r_ctrl) in
    let set a v = shadow.(a) <- v; (a, v) in
    let width_ok v = let f = (v lsr 4) land 7 in if f = 1 || f = 2 || f = 4 then v else (v land lnot 0x70) lor 0x10 in
    let writes =
      if a = r_ctrl then [ set a (v land 3) ]
      else if a = r_str_per + 1 || a = r_smp_per + 1 then begin
        let v = width_ok v in
        let lo = a - 1 in
        (if v land 15 = 0 && shadow.(lo) = 0 then [ set lo 1 ] else []) @ [ set a v ]
      end
      else if a = r_str_per || a = r_smp_per then [ set a (if v = 0 && shadow.(a + 1) land 15 = 0 then 1 else v) ]
      else if a >= r_crc_mask && a < r_crc_mask + 4 then begin
        let m = (1 lsl (v mod 33)) - 1 in
        List.init 4 (fun k -> set (r_crc_mask + k) ((m lsr (8 * k)) land 0xFF))
      end
      else [ set a v ] in
    if a >= 0x40 && a < 0x70 && ctrl land 2 = 0 then ((r_ctrl, ctrl lor 2) :: writes) @ [ (r_ctrl, ctrl) ] else writes

  let decode (s : string) =
    let n = String.length s in
    let pos = ref 1 in
    let byte () = if !pos < n then (let b = Char.code s.[!pos] in incr pos; b) else 0 in
    let bytes k = List.init k (fun _ -> byte ()) in
    let cmds = ref [] in
    let shadow = Array.init reg_space reset_value in
    let regw l (h : Host.t) _ = List.iter (fun (a, v) -> Host.wreg h a v) l in
    while !pos < n do
      let start = !pos in
      let w tgt addr data (h : Host.t) _ = Host.submit h (Host.Write { tgt; addr; data }) in
      let act =
        match byte () mod 16 with
        | 0 -> let a = byte () mod reg_space in let v = byte () in regw (legal shadow a v)
        | 1 ->
          let a = byte () mod reg_space in let k = 1 + (byte () mod 16) in
          let vs = bytes k in
          regw (List.concat (List.mapi (fun j v -> if a + j < reg_space then legal shadow (a + j) v else []) vs))
        | 2 -> let a = 2 * (byte () + (256 * (byte () mod 4))) in let k = 1 + (byte () mod 8) in w t_prog a (bytes (2 * k))
        | 3 -> let a = (4 * byte ()) + (byte () mod 4) in let k = 1 + (byte () mod 8) in w t_bank a (bytes k)
        | 4 -> let sg = byte () mod 4 in let k = 1 + (byte () mod 16) in w t_pecfg (sg lsl 8) (bytes k)
        | 5 -> let sg = byte () mod 4 in let k = 1 + (byte () mod 8) in w t_peinit (sg lsl 8) (bytes k)
        | 6 -> let a = byte () mod 16 in let v = byte () in w t_peseg a [ v ]
        | 7 -> let k = 1 + (byte () mod 8) in w t_hostin 0 (bytes k)
        | 8 ->
          let tgt = [| t_reg; t_prog; t_bank; t_hostout; t_sample; t_reg |].(byte () mod 6) in
          let a = byte () + (256 * (byte () mod 8)) in
          let k = 1 + (byte () mod 8) in
          fun h _ -> Host.submit h (Host.Read { tgt; addr = a; n = k; k = ignore })
        | 9 -> let v = byte () mod 4 in regw (legal shadow r_ctrl v)
        | 10 -> let k = 1 + (4 * byte ()) in fun h _ -> Host.submit h (Host.Idle k)
        | 11 -> w t_stream 0 (bytes 3)
        | 12 ->
          let k = 1 + (byte () mod 37) in
          let bits = List.map (fun b -> b land 1) (bytes k) in
          let ctrl = shadow.(r_ctrl) in
          fun h _ ->
            if ctrl land 2 = 0 then Host.wreg h r_ctrl (ctrl lor 2);
            Host.submit h (Host.Write { tgt = t_match; addr = 0; data = bits });
            if ctrl land 2 = 0 then Host.wreg h r_ctrl ctrl
        | 13 -> let p = byte () mod n_pads in let b = byte () in fun _ rates -> rates.(p) <- rate_of b
        | 14 -> let v = byte () and pc = byte () in fun h _ -> Host.wreg h r_restart_pc pc; Host.wreg h r_restart v
        | _ ->
          (* a thread's programme, eight words at a page and offset, its boot pc set there *)
          let t = byte () mod 4 and page = byte () mod 2 and base = byte () land 0xF8 in
          let words = List.init 8 (fun _ -> let lo = byte () in lo lor (byte () lsl 8)) in
          fun h _ ->
            Host.submit h (Host.Write { tgt = t_prog; addr = 2 * ((page lsl 8) lor base); data = List.concat_map (fun x -> [ x land 0xFF; x lsr 8 ]) words });
            Host.wreg h (r_boot_pc t) base
      in
      cmds := { span = (start, !pos - start); act } :: !cmds
    done;
    Array.of_list (List.rev !cmds)

  let max_cycles = 6000
  let tail = 400   (* clocks after the last command, for the programme to run *)

  (* the clocks of one input: the host executes the commands in order, the world flips pads *)
  let drive (s : string) ~(step : Board.t -> smp:int array -> unit) =
    let cmds = decode s in
    let b = Board.create () in
    let rates = Array.make n_pads 0.0 in
    let world = ext_world (Random.State.make [| Hashtbl.hash s |]) ~rates in
    let k = ref 0 and c = ref 0 and after = ref 0 in
    while !c < max_cycles && !after < tail do
      if Host.idle b.host then
        if !k < Array.length cmds then (cmds.(!k).act b.host rates; incr k) else incr after;
      let smp = Board.samples b ~ext:(world b.out) in
      step b ~smp;
      incr c
    done

  (* for hwfuzz: the core's samples per clock, two clocks late as the board delivers them *)
  let transduce (s : string) =
    let rows = ref [] and pipe = Queue.create () in
    Queue.push (Array.make n_pads 0) pipe; Queue.push (Array.make n_pads 0) pipe;
    drive s ~step:(fun _ ~smp ->
        Queue.push smp pipe;
        let seen = Queue.pop pipe in
        let half lo = Array.fold_left ( lor ) 0 (Array.init 8 (fun i -> seen.(lo + i) lsl (4 * i))) in
        rows := [ ("smp_lo", half 0); ("smp_hi", half 8) ] :: !rows);
    Array.of_list (List.rev !rows)

  let circuit cfg () =
    let open Hardcaml.Signal in
    let clock = input "clock" 1 and reset = input "reset" 1 in
    let lo = input "smp_lo" 32 and hi = input "smp_hi" 32 in
    let o = Chip_rtl.create ~cfg ~clock ~reset ~smp:(concat_msb [ hi; lo ]) () in
    Hardcaml.Circuit.create_exn ~name:"chip_core_fz"
      [ output "pad_lo" (select o.pad_nib 31 0); output "pad_hi" (select o.pad_nib 63 32); output "uio_oe" o.uio_oe ]

  let target cfg : Hwfuzz.target =
    { name = "chip"; circuit = circuit cfg; clock = "clock"; clear = Some "reset"; max_cycles; observer = None;
      stream = Some transduce; units = Some (fun s -> Array.to_list (Array.map (fun c -> c.span) (decode s))) }

  (* the oracle: the input on the board with feedback, specification and RTL compared every clock *)
  let replay cfg (s : string) =
    let spec = S.create ~cfg () and rtl = Chip_sim.create ~cfg () in
    let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
    let diffs = ref None and c = ref 0 in
    drive s ~step:(fun b ~smp ->
        (match Board.advance b cores ~smp ~reset:(!c < 2) with
         | [ a; o ] when !diffs = None ->
           let d = out_diffs a o in
           let d = if d = [] then state_diffs spec rtl else d in
           if d <> [] then diffs := Some (!c, d)
         | _ -> ());
        incr c);
    !diffs

  (* seeds: commands in the order a host sets the chip up, with random operands *)
  let seed_input r =
    let i n = Random.State.int r n in
    let buf = Buffer.create 512 in
    let add l = List.iter (fun x -> Buffer.add_char buf (Char.chr (x land 0xFF))) l in
    add [ 0 ];
    add [ 9; 2 ];
    for t = 0 to 3 do
      add [ 15; t; 0; 32 * t ];
      for _ = 1 to 8 do let wd = Gen.gen_programme r ~words:1 ~base:(32 * t) in add [ wd.(0) land 0xFF; wd.(0) lsr 8 ] done
    done;
    add [ 1; r_padsel 0; 16 ]; add (List.init 16 (fun _ -> i 128));
    add [ 1; r_flagsel 0; 16 ]; add (List.init 16 (fun _ -> i 32));
    for sg = 0 to 3 do
      add [ 4; sg; 7 ]; add (Array.to_list (Upe.Spec.bytes_of_op (rand_op r)) |> List.rev);
      add [ 5; sg; 1; i 256; i 256 ];
      add [ 6; (sg lsl 2) lor 2; [| 0; 1; 2; 3; 4 |].(i 5) lor (i 2 lsl 3) lor 16 lor (i 2 lsl 5) lor (i 2 lsl 6) ]
    done;
    for _ = 1 to 4 do add [ 13; i 16; i 5 ] done;
    add [ 9; 1 ];
    let open Regs in
    for _ = 1 to 12 do
      match i 6 with
      | 0 -> add [ 7; i 8 ]; add (List.init 8 (fun _ -> i 256))
      | 1 -> add [ 8; i 6; i 256; i 8; i 8 ]
      | 2 -> add [ 6; i 16; i 256 ]
      | 3 -> add [ 10; i 64 ]
      | 4 -> add [ 11; i 256; i 256; i 16 ]
      | _ -> add [ 0; i reg_space; i 256 ]
    done;
    Buffer.contents buf
end

let fuzz ~cfg ~budget ~seed ~outdir =
  Cov.enable ();
  Chip_sim.coverage := true;
  (try Unix.mkdir outdir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let r = Random.State.make [| seed |] in
  let seeds = List.init 16 (fun _ -> Fz.seed_input r) in
  let hcfg = { Hwfuzz.default_config with workers = (match Sys.getenv_opt "HWFUZZ_WORKERS" with Some w -> int_of_string w | None -> 2) } in
  let t0 = Unix.gettimeofday () in
  let res = Hwfuzz.campaign ~cfg:hcfg ~corpus:seeds ~budget ~fresh:false ~seed (Fz.target cfg) in
  pr "hwfuzz: %d executions, %d features, %d queue entries (%.0f s)\n%!" res.execs res.coverage (Array.length res.queue)
    (Unix.gettimeofday () -. t0);
  Array.iteri (fun k op -> if res.stats.uses.(k) > 0 then pr "  operator %-12s %6d uses %4d wins\n" op res.stats.uses.(k) res.stats.wins.(k))
    Hwfuzz.op_names;
  (* the oracle and the coverage: the seeds first, then every queue entry *)
  let replay_all label inputs =
    let bad = ref 0 in
    List.iteri (fun k s ->
        match Fz.replay cfg s with
        | None -> ()
        | Some (c, d) ->
          incr bad;
          let f = Printf.sprintf "%s/mismatch-%s-%d.bin" outdir label k in
          let oc = open_out_bin f in output_string oc s; close_out oc;
          pr "  %s input %d: mismatch at clock %d: %s (input in %s)\n" label k c (String.concat "; " (List.filteri (fun i _ -> i < 4) d)) f)
      inputs;
    pr "%s: %d inputs replayed against the specification, %d with mismatches\n%!" label (List.length inputs) !bad in
  replay_all "seeds" seeds;
  let acc = Option.get (Chip_sim.coverage_acc ~cfg ()) in
  let const, _ = Cov.constant_bits acc.source acc.infos in
  Cov.report ~const ~title:"RTL register coverage of the seeds" acc;
  let queue = Array.to_list (Array.map fst res.queue) in
  replay_all "queue" queue;
  Cov.report ~const ~title:"RTL register coverage of the seeds and the queue" acc;
  let oc = open_out (outdir ^ "/never.txt") in
  Cov.write_never ~const oc acc;
  close_out oc;
  List.iteri (fun k s -> let oc = open_out_bin (Printf.sprintf "%s/queue-%04d.bin" outdir k) in output_string oc s; close_out oc) queue;
  pr "queue and never-changed bits in %s\n" outdir

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
  pr "%d of %d planted integration bugs caught\n" !caught (List.length Chip_rtl.bugs);
  if !caught < List.length Chip_rtl.bugs then exit 1

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
  | [ _; "fuzz"; sizes; budget; seed; outdir ] ->
    let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' sizes)) in
    fuzz ~cfg:{ cfg with layout = Upe.Spec.layout_of_sizes sizes } ~budget:(int_of_string budget) ~seed:(int_of_string seed) ~outdir
  | [ _; "regmap"; sizes; prog_words; file ] ->
    (* every register of Tt_top.create as emitted (bin/emit.ml): its Verilog name, width and
       source line, for mapping a hardened netlist's flip-flops back to blocks (sim/gate_cov.py) *)
    Cov.enable ();
    let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' sizes)) in
    let cfg = { S.layout = Upe.Spec.layout_of_sizes sizes; prog_words = int_of_string prog_words } in
    let c = Tt_top.create ~cfg ~memories:`Macros ~name:"chip_tt" () in
    let _, infos = Cov.instrument ~labeller:Chip_sim.regfile_labeller c in
    let oc = open_out file in
    Array.iter (fun (i : Cov.reg) ->
        Printf.fprintf oc "_%d %d %s %s %s %d\n" i.uid i.width i.loc (String.map (fun c -> if c = ' ' then '_' else c) (Cov.block_of i.file))
          (if i.label = "" then "-" else i.label) i.label_off) infos;
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
      [ [| 1; 1; 1; 1 |]; [| 2; 2; 2; 2 |]; [| 3; 3; 3; 3 |]; [| 2; 2; 4; 8 |] ];
    ignore (run_design ~cfg:{ cfg with prog_words = 256 } ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:200)
  | _ -> prerr_endline "usage: lockstep.exe run N CLOCKS [SEED] | controls N CLOCKS | layouts N CLOCKS | coverage SIZES N CLOCKS SEED NEVER_FILE [wide]; run N CLOCKS SEED wide and controls N CLOCKS wide: the wide generator (Gen)"
