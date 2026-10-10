(* The lockstep's stimulus: random programmes, random PE configurations, the host's random traffic
   and the outside world on the general pads. Shared by bin/lockstep.ml (against the
   specification) and bin/gate_lockstep.ml (the extracted gates against the Hardcaml).

   [wide] (coverage-directed, added after measuring register toggle coverage with Cov) also draws
   the assists' configuration from the whole legal range rather than small values (periods,
   offsets, holdoff and timeout up to their register widths, frame lengths up to 255), uses
   16-bit host-link addresses (beyond the register space), long transfers (up to 256 bytes, which
   reach the link's count register's top bit), bursts that fill the streamer, sampler and host
   FIFOs, and a matcher configuration that a constant stream matches in full. Without [wide] the
   generator is the one every earlier result was measured with, draw for draw. *)

open Regs
module S = Chip_spec

let wide = ref false

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
      else if x < 28 then Isa2.ldd (if !wide && chance 0.2 then i 4096 else if chance 0.7 then 0 else i 30)
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


(* ---- the bit-path assists (registers 0x80-0x8D, r_es_mode bit 4) ----
   Drawn from a stream of their own, seeded from the trial's without consuming it, so that every
   draw the generator made before the assists existed is the same draw now. Profiles:
   - off (a quarter of the trials): the registers stay at reset, the chip as without the assists;
   - USB-like loopback: the serialiser's lines on uio 6 and 7 (pads 14, 15), which read back what
     the chip drives, the edge sampler on pad 15 in NRZ mode with the OR of pad 14 as its active
     input, NRZI and stuffing both ways, sync pattern 0x80, end on the line going inactive, the
     CRC on the frame after the PID;
   - Ethernet-like loopback: Manchester out on pad 14, the edge sampler in Manchester mode on it,
     pass, SFD pattern, end at the burst end;
   - random: every register random (wide: from the whole range).
   The bit path's port is one of the four, at random; the threads' random SENDs and RECVs on it
   then drive the serialiser and drain the framer. *)
let bp_rng = ref (Random.State.make [| 0 |])
let bp_profile = ref 0

(* In the loopback profiles, two threads now and then get directed programmes: a sender of frames
   (a sync or preamble, then a few bytes, runs of 1s and 0s favoured, on the bit path's port) and a
   receiver (RECV on it, OUT, and a WAITC on the end-of-frame flag). *)
let bp_threads r (h : Host.t) ~(cfg : S.config) ~pages ~ch ~sync =
  let i n = Random.State.int r n in
  let ts = i 4 in
  let tr = (ts + 1 + i 3) mod 4 in
  let byte () = match i 4 with 0 -> 0xFF | 1 -> 0x00 | 2 -> 0x7E | _ -> i 256 in
  let sender =
    List.concat_map (fun b -> [ Isa2.lda b; Isa2.send ~ch ~fail:0 ]) sync
    @ List.concat (List.init (1 + i 6) (fun _ -> [ Isa2.lda (byte ()); Isa2.send ~ch ~fail:0 ])) in
  (* the SENDs' fail targets: themselves (at dl = 0 a full FIFO makes them spin) *)
  let sender = List.mapi (fun k w -> if w lsr 12 = Isa2.op_mbx then (w land lnot 0xFF) lor (0xC0 + k) else w) sender in
  let sender = Array.of_list (sender @ [ Isa2.ldd (i 300); Isa2.waitd; Isa2.jmp 0xC0 ]) in
  let receiver = [| Isa2.recv ~ch ~fail:0xE0; Isa2.out (); Isa2.waitc ~cond:(Isa2.c_flag 0) ~fail:0xE0; Isa2.outi ~tag:1 0xEE; Isa2.jmp 0xE0 |] in
  let put t base words =
    let addr = ((pages.(t) lsl 8) lor base) land (cfg.prog_words - 1) in
    Host.submit h (Host.Write { tgt = t_prog; addr = 2 * addr; data = List.concat_map (fun w -> [ w land 0xFF; w lsr 8 ]) (Array.to_list words) });
    Host.submit h (Host.Write { tgt = t_reg; addr = r_boot_pc t; data = [ base ] }) in
  put ts 0xC0 sender;
  put tr 0xE0 receiver;
  Host.submit h (Host.Write { tgt = t_reg; addr = r_flagsel (4 * tr); data = [ fl_rx_done; fl_rx_err; fl_tx_active; fl_line_inactive ] })

let bp_setup ?(mode = "mixed") r (h : Host.t) ~cfg ~pages =
  bp_rng := Random.State.make [| Random.State.bits (Random.State.copy r); 0xb17 |];
  let r = !bp_rng in
  let i n = Random.State.int r n and chance p = Random.State.float r 1.0 < p in
  let w a l = Host.submit h (Host.Write { tgt = t_reg; addr = a; data = l }) in
  (* the ports mode keeps the segments' holding registers busy: there, mostly a loopback, so that
     the bit path's port and a busy segment behind the same port meet *)
  bp_profile := (if mode = "ports" && chance 0.8 then 1 + i 2 else i 4);
  let pnum = i 4 in
  let port () = (if chance 0.85 then 1 else 0) lor (pnum lsl 1) in
  let threads sync = if chance 0.7 then bp_threads r h ~cfg ~pages ~ch:(4 + pnum) ~sync in
  let p12 () = if !wide && chance 0.3 then i 4096 else 1 + i 8 in
  match !bp_profile with
  | 0 -> ()
  | 1 ->
    (* USB-like: P clocks per symbol; the edge sampler counts 4 sub-samples per clock *)
    let per = if chance 0.5 then 2 + i 6 else 8 + i 55 in
    let ctrl = port () lor (if chance 0.8 then 8 else 0) lor (if chance 0.15 then 16 else 0) lor 32 lor (if chance 0.2 then 64 else 0) lor 128 in
    w r_bp_ctrl
      [ ctrl; 0x01 lor (if chance 0.1 then 4 else 0); 0x26; 0x80;
        (* the line before a frame is whatever the idle pins show, so the sync's first symbol is
           decoded against a random level: often match only the last seven bits *)
        (match i 5 with 0 | 1 -> 0xFF | 2 | 3 -> 0xFE | _ -> i 256); (if chance 0.7 then 8 else i 32);
        0x05; 0x26; per land 0xFF; per lsr 8; 0x02; 0x11; 0x76 ];
    w r_es_mode [ 2 lor 8 lor 16; 0xEF; 4; 0; 0xFF; 3; min 255 (2 * per); min 255 (4 * per) ];
    w (r_padsel 14) [ src_tx_a; src_tx_b ];
    threads [ 0x80 ]
  | 2 ->
    let per = 1 + i 6 in
    let ctrl = port () lor (if chance 0.8 then 8 else 0) lor (if chance 0.15 then 16 else 0) lor 64 lor 128 lor (if chance 0.2 then 32 else 0) in
    w r_bp_ctrl
      [ ctrl; 0; 0; 0xD5; (if chance 0.8 then 0xFF else i 256); (if chance 0.7 then 0 else i 16);
        0x02; 0; per; 0; 0x16; 0x00; 0x10 ];
    w r_es_mode [ 0; 0x0E; 6 * per; 0; 16 * per; 0; 0; 0 ];
    w (r_padsel 14) [ src_tx_a; src_tx_b ];
    threads [ 0x55; 0x55; 0xD5 ]
  | _ ->
    let c = if !wide then i 256 else (i 256) land lnot (if chance 0.5 then 1 else 0) in
    let t = p12 () in
    w r_bp_ctrl
      [ c; i 32; i 64; i 256; (if chance 0.5 then 0xFF else i 256); (if chance 0.5 then i 16 else i 256);
        i 32; i 64; t land 0xFF; t lsr 8; i 64; i 64; i 128 ];
    if chance 0.5 then w r_es_mode [ i 32 ];
    if chance 0.5 then w (r_padsel (if chance 0.5 then 14 else 15)) [ (if chance 0.5 then src_tx_a else src_tx_b) lor (i 4 lsl 5) ]

(* while running: pulses, live reconfiguration, status reads *)
let bp_traffic (h : Host.t) =
  let r = !bp_rng in
  let i n = Random.State.int r n in
  let w a l = Host.submit h (Host.Write { tgt = t_reg; addr = a; data = l }) in
  match i 16 with
  | 0 | 1 | 2 -> w r_bp_pulse [ 1 + i 3 ]
  | 3 | 4 | 5 | 6 -> Host.submit h (Host.Read { tgt = t_reg; addr = r_bp_status; n = 1; k = ignore })
  | 7 -> if !bp_profile = 3 then w r_tx_per [ 1 + i 8; 0 ]
  | 8 -> if !bp_profile = 3 then w r_rx_pattern [ i 256; (if i 2 = 0 then 0xFF else i 256) ]
  (* the loopback profiles keep their configuration but for the CRC source and half duplex *)
  | 9 -> if !bp_profile = 3 then w (r_bp_ctrl + 1 + i 12) [ i 256 ]
  | 10 -> if !bp_profile = 3 then w r_bp_ctrl [ i 256 ]
  | 11 -> if !bp_profile = 3 then w r_es_mode [ i 32 ]
  | _ -> Host.submit h (Host.Read { tgt = t_reg; addr = r_bp_ctrl; n = 15; k = ignore })

(* the host's random traffic: a setup, then transactions while the programme runs *)
let setup_traffic ?(mode = "mixed") r (h : Host.t) ~(cfg : S.config) =
  let i n = Random.State.int r n and chance p = Random.State.float r 1.0 < p in
  let w = Host.wreg h in
  let block a l = Host.submit h (Host.Write { tgt = t_reg; addr = a; data = l }) in
  w r_ctrl 2;                                   (* stopped, assists held *)
  (* the programme: each thread a region of a page *)
  let pages = Array.init 4 (fun _ -> i 4) and bases = Array.init 4 (fun _ -> i 224) in
  for t = 0 to 3 do
    (* wide, ports mode: now and then a thread SENDs on every one of its issue slots, so that with
       all four doing it the mailbox path is busy every clock and a host feed write keeps waiting
       until the next host byte arrives (the dropped-write sticky bit) *)
    let words =
      if !wide && mode = "ports" && chance 0.5 then
        Array.init 30 (fun k -> if k = 29 then Isa2.jmp bases.(t) else Isa2.send ~ch:(4 + i 4) ~fail:bases.(t))
      else gen_programme ~mode r ~words:(8 + i 24) ~base:bases.(t) in
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
  if !wide then begin
    (* the whole legal range: 12-bit periods and offsets, 10-bit holdoff and timeout, 8-bit
       edge-sampler offset and period (at least 4, the sub-sample count, as the model requires
       for one bit per clock), any frame length *)
    let p12 () = if chance 0.3 then 1 + i 4095 else 1 + i 6 in
    (* Random.State.bits gives 30 bits; the CRC registers are 32 *)
    let rb32 () = (rb () lor (rb () lsl 30)) land 0xFFFF_FFFF in
    let sp = p12 () and mp = p12 () and mo = if chance 0.3 then i 4096 else i 6 in
    let ho = if chance 0.3 then i 1024 else 4 + i 12 and tmo = if chance 0.3 then 8 + i 1016 else 8 + i 60 in
    let eo = if chance 0.3 then 4 + i 252 else 4 + i 8 and ep = if chance 0.3 then 4 + i 252 else 4 + i 12 in
    block r_str_per
      ([ sp land 0xFF; (width () lsl 4) lor (sp lsr 8); i 256; i 16 ]
       @ [ mp land 0xFF; (width () lsl 4) lor (i 2 lsl 7) lor (mp lsr 8); mo land 0xFF; (i 4 lsl 4) lor (i 2 lsl 6) lor (mo lsr 8);
           (if chance 0.3 then i 256 else i 12) ]
       @ [ 0; 0; 0 ]
       @ [ i 16; i 256; ho land 0xFF; ho lsr 8; tmo land 0xFF; tmo lsr 8; eo; ep ]
       @ [ i 4; 0; 0; 0 ]
       @ le32 (rb32 () land mask) @ le32 (rb32 () land mask) @ le32 mask @ le32 (rb32 ())
       @ le32 (if chance 0.5 then 0 else rb32 () land mask)
       @ le32 (rb32 ()))
  end else
  block r_str_per
    ([ 1 + i 6; width () lsl 4; i 256; i 16 ]                                    (* 0x40 streamer *)
     @ [ 1 + i 6; (width () lsl 4) lor (i 2 lsl 7); i 6; (i 4 lsl 4) lor (i 2 lsl 6); i 12 ] (* 0x44 sampler *)
     @ [ 0; 0; 0 ]                                                               (* 0x49-0x4B *)
     @ [ i 16; i 256; 4 + i 12; 0; 8 + i 60; i 2; 4 + i 8; 4 + i 12 ]           (* 0x4C edge sampler *)
     @ [ i 4; 0; 0; 0 ]                                                          (* 0x54 CRC control *)
     @ le32 (rb () land mask) @ le32 (rb () land mask) @ le32 mask @ le32 (rb ())
     @ le32 (if chance 0.5 then 0 else rb () land mask)
     @ le32 (rb () lor (rb () lsl 30)));                                         (* 0x6C NCO *)
  (* wide: now and then the matcher's chain as threshold 16 (shifted in first, msb first), then
     every cell's (t, m) = (0, 1), last cell first: a run of zeros matches all 16 cells *)
  let full_match = !wide && chance 0.3 in
  Host.submit h (Host.Write { tgt = t_match; addr = 0;
                              data = (if full_match then [ 1; 0; 0; 0; 0 ] @ List.concat (List.init 16 (fun _ -> [ 0; 1 ]))
                                      else List.init 37 (fun _ -> i 2)) });
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
  bp_setup ~mode r h ~cfg ~pages;
  w r_ctrl 0;                                    (* release the assists *)
  w r_ctrl 1                                     (* run *)

(* wide only: transactions that the uniform traffic below does not make *)
let wide_traffic r (h : Host.t) =
  let i n = Random.State.int r n in
  let ignore_k _ = () in
  match i 9 with
  | 0 -> Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init (17 + i 24) (fun _ -> i 256) })   (* overflow *)
  | 1 -> Host.submit h (Host.Read { tgt = t_hostout; addr = 0; n = 2 * (4 + i 7); k = ignore_k })
  | 2 -> Host.submit h (Host.Read { tgt = t_reg; addr = i 65536 land lnot 0xFF lor i 256; n = 1 + i 8; k = ignore_k })  (* beyond the register space *)
  | 3 -> Host.submit h (Host.Read { tgt = t_reg; addr = 0; n = 128 + i 129; k = ignore_k })   (* up to the count's top bit *)
  | 4 -> for _ = 1 to 5 + i 3 do Host.submit h (Host.Write { tgt = t_stream; addr = 0; data = [ i 256; i 256; i 16 ] }) done
  | 5 -> Host.submit h (Host.Read { tgt = t_sample; addr = 0; n = 3 * (2 + i 4); k = ignore_k })
  | 6 -> if i 8 = 0 then Host.submit h (Host.Write { tgt = t_hostin; addr = 0; data = List.init 256 (fun _ -> i 256) })
  | 7 -> Host.submit h (Host.Write { tgt = t_peseg; addr = i 65536; data = [ i 256 ] })
  | _ -> Host.submit h (Host.Write { tgt = (if i 2 = 0 then t_pecfg else t_peinit); addr = i 65536; data = List.init (1 + i 8) (fun _ -> i 256) })

let running_traffic ?(mode = "mixed") r (h : Host.t) =
  if !bp_profile <> 0 && Random.State.int !bp_rng 12 = 0 then bp_traffic h else
  if !wide && Random.State.int r 8 = 0 then wide_traffic r h else
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
(* [rates]: per pad, the chance per quarter of a flip. Wide adds a slow rate per trial (see
   [pad_rates]), which leaves long constant runs for the edge sampler and the matcher. *)
let pad_rates r = Array.init n_pads (fun _ -> List.nth ((if !wide then [ 0.002 ] else []) @ [ 0.0; 0.01; 0.05; 0.2 ]) (Random.State.int r (if !wide then 5 else 4)))

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

