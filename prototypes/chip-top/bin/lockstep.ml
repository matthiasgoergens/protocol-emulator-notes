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

open Regs
module S = Chip_spec

let pr = Printf.printf

(* ---- random programmes ---- *)

(* Generators, chosen per trial (seed mod the number of modes), each biased towards the paths
   that uniform traffic reaches rarely:
   - mixed: everything;
   - ports: threads SEND and RECV on the ports while the host writes the same segments' feeds;
   - host: threads OUT and IN while the host polls HOSTOUT and fills HOSTIN;
   - memory: the threads' first words are memory and FIFO instructions (fetched again on every
     clock in clear), and the host reads and writes the bank and the store while stopped;
   - race: rare OUTs while the host polls HOSTOUT without pause, so that an entry arrives
     between the two bytes of a read. *)
let modes = [| "mixed"; "ports"; "host"; "memory"; "race" |]

let gen_programme ?(mode = "mixed") r ~words ~base =
  let i n = Random.State.int r n and chance p = Random.State.float r 1.0 < p in
  let a () = base + i words in
  let pick l = List.nth l (i (List.length l)) in
  Array.init words (fun k ->
      let x = i 100 in
      let x =
        match mode with
        | "ports" -> if chance 0.5 then 53 + i 16 else x
        | "host" -> if chance 0.4 then (if i 3 = 0 then 50 else 45 + i 5) else x
        | "memory" -> if k = 0 then List.nth [ 87; 87; 83; 50; 64 ] (i 5) else x
        | "race" -> if x >= 45 && x < 50 && i 4 > 0 then 37 else if x < 28 && x >= 23 then 24 else x
        | _ -> x
      in
      if x < 9 then Isa2.setp ~q:(i 4) ~mask:(i 256) ~value:(i 2) ~oe:(i 2) ()
      else if x < 16 then Isa2.sho ~od:(i 2) ~pair:(i 2) ~psel:(i 2) ~cap:(i 2) ~q:(i 4) ~pin:(i 8) ~msb:(i 2) ()
      else if x < 19 then Isa2.shi ~quad:(i 2) ~pin:(i 8) ~msb:(i 2) ()
      else if x < 23 then Isa2.ldc (i 20)
      else if x < 28 then Isa2.ldd (if chance 0.7 then 0 else i 30)
      else if x < 33 then Isa2.lda (if chance 0.5 then i 8 else i 256)
      else if x < 36 then Isa2.waitp ~pin:(i 8) ~value:(i 2) ~fail:(a ())
      else if x < 38 then Isa2.waitd
      else if x < 42 then Isa2.jmp (a ())
      else if x < 45 then Isa2.jnz (a ())
      else if x < 50 then (if chance 0.5 then Isa2.out ~tag:(i 8) () else Isa2.outi ~tag:(i 8) (i 256))
      else if x < 53 then Isa2.in_
      else if x < 62 then Isa2.send ~ch:(pick [ 4; 5; 6; 7; 4; 5; 0; 1; 2; 3 ]) ~fail:(a ())
      else if x < 69 then Isa2.recv ~ch:(pick [ 4; 5; 6; 7; 4; 5; 0; 1; 2; 3 ]) ~fail:(a ())
      else if x < 76 then Isa2.waitc ~cond:(pick [ 12; 13; 14; 15; 12; 13; 9; 10; 11; i 16 ]) ~fail:(a ())
      else if x < 79 then Isa2.skne (i 4)
      else if x < 81 then Isa2.skeq (i 4)
      else if x < 83 then Isa2.cnta
      else if x < 87 then Isa2.ldb
      else if x < 91 then Isa2.stb
      else if x < 93 then Isa2.bank (i 4)
      else if x < 95 then Isa2.cfg (if chance 0.5 then Isa2.cfg_round_latch else i 128)
      else if x < 96 then Isa2.fine (i 256)
      else Isa2.nop)

(* ---- random PE configurations (from the array's own generator) ---- *)

let rand_op r : Upe.Spec.op =
  let i n = Random.State.int r n and b () = Random.State.bool r in
  { xsel = i 4; sinsel = i 4; ysel = i 4; ymod = i 4; gsel = i 8; bitsel = i 16; pairlo = b (); alu = i 8;
    cin_lane = b (); swb = i 4; pwb = i 4; fwb = i 4; lout = i 4; lane_bc = b (); del = Random.State.int r 4 = 0;
    stream = b (); tap_p = b (); follow = Random.State.int r 4 = 0; ashr = (if b () then 0 else i 16); k = i 0x10000 }

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

(* the host's random traffic: a setup, then transactions while the programme runs *)
let setup_traffic ?(mode = "mixed") r (h : Host.t) ~(cfg : S.config) =
  let i n = Random.State.int r n and chance p = Random.State.float r 1.0 < p in
  let w = Host.wreg h in
  let block a l = Host.submit h (Host.Write { tgt = t_reg; addr = a; data = l }) in
  w r_ctrl 2;                                   (* stopped, assists held *)
  (* the programme: each thread a region of a page *)
  let pages = Array.init 4 (fun _ -> i 4) and bases = Array.init 4 (fun _ -> i 224) in
  for t = 0 to 3 do
    let words = gen_programme ~mode r ~words:(8 + i 24) ~base:bases.(t) in
    let addr = ((pages.(t) lsl 8) lor bases.(t)) land (cfg.prog_words - 1) in
    Host.submit h (Host.Write { tgt = t_prog; addr = 2 * addr;
                                data = List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) (Array.to_list words) })
  done;
  block (r_boot_pc 0) (Array.to_list bases @ [ Array.fold_left ( lor ) 0 (Array.mapi (fun t p -> p lsl (2 * t)) pages) ]);
  (* pads, pins, sampler pins, flags *)
  block (r_padsel 0)
    (List.init 16 (fun _ -> i 128) @ List.init 8 (fun _ -> i 16) @ List.init 4 (fun _ -> i 16) @ [ i 2 ]);
  block (r_flagsel 0) (List.init 16 (fun _ -> if chance 0.8 then i 17 else i 32));
  (* the assists, 0x40..0x6F *)
  let width () = List.nth [ 1; 2; 4 ] (i 3) in
  let width_crc = List.nth [ 5; 8; 15; 16; 32 ] (i 5) in
  let mask = if width_crc = 32 then 0xFFFF_FFFF else (1 lsl width_crc) - 1 in
  let le32 v = List.init 4 (fun k -> (v lsr (8 * k)) land 0xFF) in
  let rb () = Random.State.bits r in
  block r_str_per
    ([ 1 + i 6; width () lsl 4; i 256; i 16 ]                                    (* 0x40 streamer *)
     @ [ 1 + i 6; (width () lsl 4) lor (i 2 lsl 7); i 6; (i 4 lsl 4) lor (i 2 lsl 6); i 12 ] (* 0x44 sampler *)
     @ [ 0; 0; 0 ]                                                               (* 0x49-0x4B *)
     @ [ i 16; i 256; 4 + i 12; 0; 8 + i 60; i 2; 4 + i 8; 4 + i 12 ]           (* 0x4C edge sampler *)
     @ [ i 4; 0; 0; 0 ]                                                          (* 0x54 CRC control *)
     @ le32 (rb () land mask) @ le32 (rb () land mask) @ le32 mask @ le32 (rb ())
     @ le32 (if chance 0.5 then 0 else rb () land mask)
     @ le32 (rb () lor (rb () lsl 30)));                                         (* 0x6C NCO *)
  Host.submit h (Host.Write { tgt = t_match; addr = 0; data = List.init 37 (fun _ -> i 2) });
  (* the array: configuration and init chains, segment registers *)
  let l = cfg.layout in
  for sg = 0 to 3 do
    let n = l.end_.(sg) - l.start.(sg) + 1 in
    let bytes = List.concat (List.init n (fun _ -> List.rev (Array.to_list (Upe.Spec.bytes_of_op (rand_op r))))) in
    Host.submit h (Host.Write { tgt = t_pecfg; addr = sg lsl 8; data = bytes });
    Host.submit h (Host.Write { tgt = t_peinit; addr = sg lsl 8; data = List.init (2 * n) (fun _ -> i 256) });
    let src = if mode = "ports" then List.nth [ 2; 2; 2; 0 ] (i 4) else List.nth [ 0; 0; 1; 2; 2; 3; 5 ] (i 7) in
    let ctrl = src lor (i 2 lsl 3) lor (if chance 0.85 then 16 else 0) lor (i 2 lsl 5) lor (i 2 lsl 6) in
    Host.submit h (Host.Write { tgt = t_peseg; addr = (sg lsl 2) lor 2; data = [ ctrl ] });
    if chance 0.4 then Host.submit h (Host.Write { tgt = t_peseg; addr = (sg lsl 2) lor 3; data = [ List.nth [ 1; 2; 3; 5; 9 ] (i 5) ] })
  done;
  Host.submit h (Host.Write { tgt = t_bank; addr = (if mode = "memory" then 0 else i 1024); data = List.init 16 (fun _ -> i 256) });
  w r_ctrl 0;                                    (* release the assists *)
  w r_ctrl 1                                     (* run *)

let running_traffic ?(mode = "mixed") r (h : Host.t) =
  let i n = Random.State.int r n in
  let w = Host.wreg h in
  let ignore_k _ = () in
  let x = i 22 in
  let x =
    match mode with
    | "ports" -> if i 2 = 0 then List.nth [ 9; 10; 13 ] (i 3) else x
    | "host" -> if i 2 = 0 then List.nth [ 0; 3; 4; 3 ] (i 4) else x
    | "memory" -> if i 2 = 0 then 18 else x
    | "race" -> if i 4 > 0 then 3 else x
    | _ -> x
  in
  match x with
  | 0 | 1 | 2 -> Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init (1 + i 4) (fun _ -> i 256) })
  | 3 | 4 -> Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 2 * (1 + i 3); k = ignore_k })
  | 5 | 6 -> Host.submit h (Host.Read { tgt = t_reg; addr = i reg_space; n = 1 + i 4; k = ignore_k })
  | 7 -> Host.submit h (Host.Write { tgt = t_stream; addr = 0; data = [ i 256; i 256; i 16 ] })
  | 8 -> Host.submit h (Host.Read { tgt = t_sample; addr = 0; n = 4; k = ignore_k })
  | 9 | 10 -> Host.submit h (Host.Write { tgt = t_peseg; addr = (i 4 lsl 2) lor (List.nth [ 0; 1; 1; 2; 3 ] (i 5)); data = [ i 256 ] })
  | 11 -> Host.submit h (Host.Write { tgt = (if i 2 = 0 then t_pecfg else t_peinit); addr = i 4 lsl 8; data = [ i 256 ] })
  | 12 -> w r_restart (i 16); w r_restart_pc (i 256)
  | 13 -> w r_port_reset (i 16)
  | 14 -> w r_crc_start 0
  | 15 -> Host.submit h (Host.Read { tgt = t_reg; addr = r_status; n = 1; k = ignore_k }); w r_status 0
  | 16 -> Host.wreg32 h r_nco_inc (Random.State.bits r)
  | 17 -> w (r_flagsel (i 16)) (i 32); w (r_padsel (List.nth general_out_pads (i 10))) (i 128)
  | 18 ->
    (* stop, touch the memories, start again *)
    w r_ctrl 0;
    Host.submit h (Host.Write { tgt = t_prog; addr = 2 * i 1024; data = [ i 256; i 256 ] });
    Host.submit h (Host.Read { tgt = t_prog; addr = i 2048; n = 2; k = ignore_k });
    let ba () = if i 2 = 0 || mode = "memory" then i 4 else i 1024 in
    Host.submit h (Host.Write { tgt = t_bank; addr = ba (); data = [ i 256 ] });
    Host.submit h (Host.Idle (i 30));
    Host.submit h (Host.Read { tgt = t_bank; addr = ba (); n = 2; k = ignore_k });
    w r_ctrl 1
  | 19 -> Host.submit h (Host.Write { tgt = t_prog; addr = i 2048; data = [ i 256 ] })   (* refused while running *)
  | 20 ->
    (* hold the assists, change their configuration, release *)
    w r_ctrl 3; w r_es_mode (i 16); w r_smp_per (1 + i 5);
    Host.submit h (Host.Write { tgt = t_match; addr = 0; data = [ i 2; i 2; i 2 ] }); w r_ctrl 1
  | _ -> Host.submit h (Host.Idle (i 40))

(* the outside world: each general input pad flips with a per-trial rate per quarter *)
let ext_world r ~rates =
  let lv = Array.make n_pads 0 in
  fun (out : S.outputs) ->
    let smp = Array.make n_pads 0 in
    List.iter
      (fun p ->
        let n = ref 0 in
        for q = 0 to 3 do
          if Random.State.float r 1.0 < rates.(p) then lv.(p) <- 1 - lv.(p);
          n := !n lor (lv.(p) lsl q)
        done;
        smp.(p) <- !n)
      [ 0; 1; 2; 3; 4; 5; 6; 7; 14; 15 ];
    (* a uio pad the chip drives reads back what it drives *)
    List.iter (fun p -> smp.(p) <- Board.resolve_uio out p ~ext:smp.(p)) [ 14; 15 ];
    smp

exception Mismatch of int * string list

(* Runs one trial; returns the clock of the first mismatch and the differences, or None. *)
let run_trial ?(compare_state = true) { cfg; clocks; seed } =
  let r = Random.State.make [| seed |] in
  let r_gen = r in
  let mode = modes.(seed mod Array.length modes) in
  let spec = S.create ~cfg () and rtl = Chip_sim.create ~cfg () in
  let cores = [ Board.spec_core spec; Board.rtl_core rtl ] in
  let b = Board.create () in
  let rates = Array.init n_pads (fun _ -> List.nth [ 0.0; 0.01; 0.05; 0.2 ] (Random.State.int r 4)) in
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

let () =
  let cfg = S.default_config in
  match Array.to_list Sys.argv with
  | [ _; "run"; n; c ] -> exit (if run_design ~cfg ~trials:(int_of_string n) ~clocks:(int_of_string c) ~seed0:1 then 0 else 1)
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
  | _ -> prerr_endline "usage: lockstep.exe run N CLOCKS [SEED] | controls N CLOCKS | layouts N CLOCKS"
