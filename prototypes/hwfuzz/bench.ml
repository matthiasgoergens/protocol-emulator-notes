(* Benchmarks for hwfuzz. Each target is an ordinary Hardcaml circuit; the fuzzer knows nothing
   about it beyond clock and clear names. The observer doubles as the oracle: feature 1 once the
   target's goal output is high. *)
open Hardcaml

(* A combination lock: [n] strobed key bytes in order open it. The state is not an output. *)
let lock n () =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let data = input "data" 8 and strobe = input "strobe" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let st = Random.State.make [| 4242; n |] in
  let keys = List.init n (fun _ -> Random.State.int st 256) in
  let w = Base.Int.ceil_log2 (n + 1) in
  let state = wire w in
  let key = mux state (List.map (of_int ~width:8) keys @ [ zero 8 ]) in
  let next = mux2 (state ==:. n) state (mux2 strobe (mux2 (data ==: key) (state +:. 1) (zero w)) state) in
  state <== reg spec next;
  Circuit.create_exn ~name:"lock" [ output "open" (state ==:. n) ]

(* A packet protocol: 0xA5, a length byte (payload length = low 3 bits + 1), the payload, and a
   checksum byte equal to the length byte plus the payload, mod 256. Three valid packets whose
   first payload bytes are 'G', 'O', '!' in a row open it; any other valid packet starts over.
   Bytes arrive on [data] when [valid] is high. *)
let packet () =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let data = input "data" 8 and valid = input "valid" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let ps = wire 2 and count = wire 4 and len = wire 4 and sum = wire 8 and first = wire 8 and cmd = wire 2 in
  let idle = ps ==:. 0 and in_len = ps ==:. 1 and in_payload = ps ==:. 2 and in_check = ps ==:. 3 in
  let last_payload = in_payload &: (count +:. 1 ==: len) in
  let accept = valid &: in_check &: (data ==: sum) in
  let expected = mux cmd [ of_char 'G'; of_char 'O'; of_char '!'; zero 8 ] in
  let ps_next =
    mux2 (~:valid) ps
      (mux2 idle (mux2 (data ==:. 0xA5) (of_int ~width:2 1) (zero 2))
         (mux2 in_len (of_int ~width:2 2) (mux2 last_payload (of_int ~width:2 3) (mux2 in_payload ps (zero 2))))) in
  ps <== reg spec ps_next;
  count <== reg spec (mux2 (valid &: in_len) (zero 4) (mux2 (valid &: in_payload) (count +:. 1) count));
  len <== reg spec (mux2 (valid &: in_len) (uresize (select data 2 0) 4 +:. 1) len);
  sum <== reg spec (mux2 (valid &: in_len) data (mux2 (valid &: in_payload) (sum +: data) sum));
  first <== reg spec (mux2 (valid &: in_payload &: (count ==:. 0)) data first);
  let cmd_next = mux2 (cmd ==:. 3) cmd
      (mux2 accept (mux2 (first ==: expected) (cmd +:. 1) (mux2 (first ==: of_char 'G') (of_int ~width:2 1) (zero 2))) cmd) in
  cmd <== reg spec cmd_next;
  Circuit.create_exn ~name:"packet" [ output "open" (cmd ==:. 3) ]

let goal () =
  let hit = ref false in
  { Hwfuzz.observe = (fun ~cycle:_ get -> if get "open" = 1 then hit := true);
    finish = (fun () -> if !hit then [ 1 ] else []) }


(* ---- the USB full-speed device prototype, through a host transducer and an oracle ---- *)

(* Input after byte 0: packets, each a control byte then its bytes. Control: low 4 bits = length - 1,
   bit 4 = repair checksums (token CRC5 over the two bytes after the PID, data CRC16 appended to
   the payload), bits 5..7 = idle gap after the packet, 16 * (1 + g) bit times, during which the
   device may answer. The packet is line-coded by the independent host model (sync, stuffing,
   NRZI, EOP, 4 samples per bit). This is the AFL++ post-processor idea in hardware-fuzzing form. *)
let usb_stream ~repair (s : string) =
  let rows = ref [] in
  let put (l : Usb.Host.line) =
    let dp, dm = match l with J -> 1, 0 | K -> 0, 1 | SE0 -> 0, 0 in
    rows := [ ("dp_in", dp); ("dm_in", dm) ] :: !rows in
  for _ = 1 to 40 do put J done;
  let i = ref 1 in
  let n = String.length s in
  while !i < n do
    let c = Char.code s.[!i] in
    let len = min (1 + (c land 15)) (n - !i - 1) in
    let bytes = List.init len (fun k -> Char.code s.[!i + 1 + k]) in
    i := !i + 1 + len;
    let bytes =
      if not (repair && c land 16 <> 0) then bytes
      else match bytes with
        | pid :: b1 :: b2 :: _ when List.mem pid [ 0xE1; 0x69; 0x2D; 0xA5 ] ->
          Usb.Host.token pid ~addr:(b1 land 0x7F) ~ep:(((b2 land 7) lsl 1) lor (b1 lsr 7))
        | pid :: payload when List.mem pid [ 0xC3; 0x4B ] -> Usb.Host.data_packet pid payload
        | _ -> bytes in
    if bytes <> [] then List.iter put (Usb.Host.to_samples (Usb.Host.encode bytes));
    for _ = 1 to 4 * 16 * (1 + (c lsr 5)) do put J done
  done;
  (* trailing idle, so a reply to the last packet completes and gets checked *)
  for _ = 1 to 4 * 64 do put J done;
  Array.of_list (List.rev !rows)

(* The oracle: whatever the device transmits must decode (valid stuffing, ends in SE0), carry a
   well-formed PID, and, for data packets, a correct CRC16. Also reports milestones as features:
   200 + response PID, 500 + a newly set address, 700 once configured; 1 for a violation. *)
let usb_observer () =
  let seg = ref [] and in_tx = ref false and fs = Hashtbl.create 16 in
  let check () =
    let arr = Array.of_list (List.rev !seg) in
    seg := [];
    let first_k = let rec f i = if i >= Array.length arr then -1 else if arr.(i) = Usb.Host.K then i else f (i + 1) in f 0 in
    let bad = match (if first_k < 0 then None else Usb.Host.decode arr first_k) with
      | None | Some [] -> true
      | Some (pid :: rest) ->
        Hashtbl.replace fs (200 + pid) ();
        let pid_ok = pid land 15 = (lnot (pid lsr 4)) land 15 in
        let crc_ok = if List.mem pid [ 0xC3; 0x4B ] then
            (match List.rev rest with
             | hi :: lo :: rpayload ->
               let c = (lnot (Usb.Host.crc16 (Usb.Host.bits_of_bytes (List.rev rpayload)))) land 0xFFFF in
               c = lo lor (hi lsl 8)
             | _ -> false)
          else rest = [] in
        not (pid_ok && crc_ok) in
    if bad then Hashtbl.replace fs 1 () in
  { Hwfuzz.observe = (fun ~cycle:_ get ->
      let oe = get "oe" = 1 in
      if oe then begin
        in_tx := true;
        seg := (match get "dp_out", get "dm_out" with 1, 0 -> Usb.Host.J | 0, 1 -> K | _ -> SE0) :: !seg
      end else if !in_tx then (in_tx := false; check ());
      let a = get "addr" in if a <> 0 then Hashtbl.replace fs (500 + a) ();
      if get "configured" = 1 then Hashtbl.replace fs 700 ());
    (* a transmission still running when the input ends cannot be judged: it was cut off, not
       malformed (this was a false positive, found by the first long campaign) *)
    finish = (fun () -> Hashtbl.fold (fun k () acc -> k :: acc) fs []) }

(* A planted defect for checking the oracle and measuring depth: once the device has an address,
   the 30th cycle of every transmission is forced to SE0. Reaching it needs a complete
   SET_ADDRESS exchange with correct CRCs. *)
let usb_faulty () =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let dp_in = input "dp_in" 1 and dm_in = input "dm_in" 1 in
  let dp, dm, oe, addr, configured = Usb.Usb_dev.create ~clock ~clear ~dp_in ~dm_in in
  let spec = Reg_spec.create ~clock ~clear () in
  let n = reg_fb spec ~width:8 ~f:(fun c -> mux2 oe (mux2 (c ==:. 255) c (c +:. 1)) (zero 8)) in
  let hit = oe &: (addr <>:. 0) &: (n ==:. 30) in
  Circuit.create_exn ~name:"usb_faulty"
    [ output "dp_out" (dp &: ~:hit); output "dm_out" (dm &: ~:hit); output "oe" oe; output "addr" addr;
      output "configured" configured ]

(* the packets of a USB input: each is a control byte and its bytes *)
let usb_units (s : string) =
  let n = String.length s in
  let rec go i acc = if i >= n then List.rev acc
    else let l = min (2 + (Char.code s.[i] land 15)) (n - i) in go (i + l) ((i, l) :: acc) in
  go 1 []

let usb_target ?(faulty = false) ?(units = false) ~repair () =
  { Hwfuzz.name = "usb"; circuit = (if faulty then usb_faulty else Usb.Usb_dev.circuit); clock = "clock"; clear = Some "clear";
    max_cycles = 16_000; observer = Some usb_observer; stream = Some (usb_stream ~repair);
    units = (if units then Some usb_units else None) }

(* one GET_DESCRIPTOR(device) control transfer: SETUP, DATA0, IN, ACK *)
let usb_get_descriptor =
  let pkt ?(gap = 1) bytes =
    String.make 1 (Char.chr (((List.length bytes - 1) land 15) lor 16 lor (gap lsl 5)))
    ^ String.concat "" (List.map (fun b -> String.make 1 (Char.chr b)) bytes) in
  "\000" ^ pkt [ 0x2D; 0; 0 ] ^ pkt ~gap:2 [ 0xC3; 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ]
  ^ pkt ~gap:3 [ 0x69; 0; 0 ] ^ pkt ~gap:1 [ 0xD2 ]

(* A known-good session from the prototype's own test: SETUP GET_DESCRIPTOR(device), IN, then
   SET_ADDRESS 5 and its status stage. Used to check the transducer and oracle before fuzzing. *)
let usb_session =
  let pkt ?(gap = 1) ?(repair = true) bytes =
    String.make 1 (Char.chr (((List.length bytes - 1) land 15) lor (if repair then 16 else 0) lor (gap lsl 5)))
    ^ String.concat "" (List.map (fun b -> String.make 1 (Char.chr b)) bytes) in
  "\000"
  ^ pkt [ 0x2D; 0; 0 ] ^ pkt ~gap:2 [ 0xC3; 0x80; 0x06; 0x00; 0x01; 0x00; 0x00; 0x40; 0x00 ]
  ^ pkt ~gap:3 [ 0x69; 0; 0 ] ^ pkt ~gap:1 [ 0xD2 ]
  ^ pkt [ 0x2D; 0; 0 ] ^ pkt ~gap:2 [ 0xC3; 0x00; 0x05; 0x05; 0x00; 0x00; 0x00; 0x00; 0x00 ]
  ^ pkt ~gap:3 [ 0x69; 0; 0 ] ^ pkt ~gap:1 [ 0xD2 ]


(* ---- the 10BASE-T receiver against the independent model decoder, with ground truth ---- *)

let eth_h = 3   (* 60 MHz: three cycles per half bit *)

(* what the transducer sent, for the observer of the same execution (same domain) *)
let eth_truth : (int list * int array) ref Domain.DLS.key = Domain.DLS.new_key (fun () -> ref ([], [||]))

(* Input after byte 0: a length byte (payload 1..64 bytes), the payload, then perturbation records
   of 3 bytes: a position (16 bits, modulo the frame's length) and a kind: 0 an edge one cycle
   late, 1 one cycle early, 2 a one-cycle glitch, 3 activity lost for 1..4 cycles with the line
   near zero, 4..7 activity lost for 1..4 cycles while the line keeps its level (squelch off,
   polarity still visible). The comparator is modelled with hysteresis: near zero it keeps its
   last output, as a real line comparator does, rather than reading low. The frame is
   the payload plus its FCS, line-coded by the model (preamble, SFD, Manchester, TP_IDL). *)
let eth_stream (s : string) =
  let n = String.length s in
  let len = if n > 1 then 1 + Char.code s.[1] mod 64 else 1 in
  let payload = List.init len (fun k -> if 2 + k < n then Char.code s.[2 + k] else 0) in
  let smp = Array.of_list (Eth.Eth_model.encode_frame ~h:eth_h payload) in
  let m = Array.length smp in
  let act = Array.map (fun v -> v <> 0) smp in
  let i = ref (2 + len) in
  while !i + 2 < n do
    let pos = ((Char.code s.[!i] lsl 8) lor Char.code s.[!i + 1]) mod m and kind = Char.code s.[!i + 2] in
    (match kind land 7 with
     | 0 -> if pos > 0 then smp.(pos) <- smp.(pos - 1)
     | 1 -> if pos + 1 < m then smp.(pos) <- smp.(pos + 1)
     | 2 -> smp.(pos) <- - smp.(pos)
     | 3 -> for k = pos to min (m - 1) (pos + (kind lsr 3) land 3) do smp.(k) <- 0; act.(k) <- false done
     | _ -> for k = pos to min (m - 1) (pos + (kind lsr 3) land 3) do act.(k) <- false done);
    i := !i + 3
  done;
  (* the model sees a sample of 0 wherever activity is lost; the RTL sees the comparator and flag *)
  let model_smp = Array.mapi (fun k v -> if act.(k) then v else 0) smp in
  let pad a z = Array.concat [ Array.make 20 z; a; Array.make 60 z ] in
  let smp = pad smp 0 and act = pad act false in
  (Domain.DLS.get eth_truth) := (payload @ Eth.Eth_model.fcs_bytes payload, pad model_smp 0);
  let last = ref 0 in
  Array.mapi (fun k v ->
    if v > 0 then last := 1 else if v < 0 then last := 0;
    [ ("rx", !last); ("rx_active", if act.(k) then 1 else 0) ]) smp

(* Verdicts, as observed features: 1 the RTL accepts (good CRC) bytes that were not sent;
   2 the model decodes the sent frame but the RTL does not accept it; 3 the RTL accepts it but the
   model does not; 20 the RTL accepts the frame, 21 the model decodes it. *)
let eth_observer () =
  let cur = ref [] and frames = ref [] in
  { Hwfuzz.observe = (fun ~cycle:_ get ->
      if get "byte_valid" = 1 then cur := get "rx_byte" :: !cur;
      if get "frame_end" = 1 then (frames := (List.rev !cur, get "crc_ok" = 1) :: !frames; cur := []));
    finish = (fun () ->
      let truth, smp = !(Domain.DLS.get eth_truth) in
      let model_ok = List.mem truth (Eth.Eth_model.decode ~h:eth_h smp) in
      let rtl_ok = List.exists (fun (bs, ok) -> ok && bs = truth) !frames in
      let false_accept = List.exists (fun (bs, ok) -> ok && bs <> truth) !frames in
      List.filter_map Fun.id
        [ (if false_accept then Some 1 else None); (if model_ok && not rtl_ok then Some 2 else None);
          (if rtl_ok && not model_ok then Some 3 else None); (if rtl_ok then Some 20 else None);
          (if model_ok then Some 21 else None) ]) }

let eth_target =
  { Hwfuzz.name = "eth"; circuit = (fun () -> Eth.Eth_rx.circuit ~h:eth_h); clock = "clock"; clear = Some "clear";
    max_cycles = 20_000; observer = Some eth_observer; stream = Some eth_stream; units = None }

let target name =
  let circuit, max_cycles = match name with
    | "lock4" -> lock 4, 256 | "lock8" -> lock 8, 256 | "packet" -> packet, 512
    | "usb" | "usb-raw" | "usb-faulty" | "usb-units" | "usb-faulty-units" -> Usb.Usb_dev.circuit, 0
    | "eth" -> (fun () -> Eth.Eth_rx.circuit ~h:eth_h), 0 | _ -> failwith ("unknown target " ^ name) in
  if name = "eth" then eth_target else
  if name = "usb" then usb_target ~repair:true () else
  if name = "usb-raw" then usb_target ~repair:false () else
  if name = "usb-faulty" then usb_target ~faulty:true ~repair:true () else
  if name = "usb-units" then usb_target ~units:true ~repair:true () else
  if name = "usb-faulty-units" then usb_target ~faulty:true ~units:true ~repair:true () else
  { Hwfuzz.name; circuit; clock = "clock"; clear = Some "clear"; max_cycles; observer = Some goal; stream = None; units = None }

(* configuration name -> (config, engines, sync, fresh) *)
let config name =
  let d = Hwfuzz.default_config in
  match name with
  | "random" -> d, 1, false, true
  | "coverage" -> { d with dict = false; i2s = false }, 1, false, false
  | "dictionary" -> { d with i2s = false }, 1, false, false
  | "i2s" -> { d with pulses = 0 }, 1, false, false
  | "i2s+pulse" -> { d with pulses = 1 }, 1, false, false
  | "full" -> d, 1, false, false
  | "single-i2s" -> { d with multi_i2s = false }, 1, false, false
  | "restarts4" -> d, 4, false, false
  | "islands4" -> d, 4, true, false
  | _ -> failwith ("unknown config " ^ name)

let () =
  match Array.to_list Sys.argv with
  | [ _; "sweep"; tname; cname; budget; seeds ] ->
    let t = target tname and (cfg, k, sync, fresh) = config cname in
    let seeds = List.init (int_of_string seeds) (fun i -> i + 1) in
    let hits = List.map (fun seed ->
      let r = Hwfuzz.campaign ~cfg ~k ~sync ~budget:(int_of_string budget) ~fresh ~seed t in
      let hit = List.assoc_opt 1 r.first_hit in
      Printf.printf "%s %s seed %d: %s coverage %d queue %d\n%!" tname cname seed
        (match hit with Some e -> Printf.sprintf "opened at %d," e | None -> "not opened,") r.coverage (Array.length r.queue);
      hit) seeds in
    let opened = List.filter_map Fun.id hits |> List.sort compare in
    let median = match opened with [] -> "-" | l -> string_of_int (List.nth l (List.length l / 2)) in
    Printf.printf "SUMMARY %s %s budget %s: opened %d of %d, median executions to open %s\n%!"
      tname cname budget (List.length opened) (List.length seeds) median
  | [ _; "usbcheck" ] ->
    List.iter (fun (name, t) ->
    let inst = Hwfuzz.instrument t in
    (* the session, then an IN to the new address 5, which the device answers (NAK) *)
    let r = Hwfuzz.execute t inst (usb_session ^ "\050\105\005\000") in
    Printf.printf "%s: " name;
    Printf.printf "known-good session: %d cycles, observed %s\n" r.cycles
      (String.concat " " (List.map (fun f -> if f >= 700 then "configured" else if f >= 500 then Printf.sprintf "addr=%d" (f - 500)
                                              else if f >= 200 then Printf.sprintf "pid=%02x" (f - 200) else "VIOLATION")
                            (List.sort compare r.observed)))) [ ("device", usb_target ~repair:true ()); ("planted fault", usb_target ~faulty:true ~repair:true ()) ]
  | _ :: "usbfuzz" :: tname :: cname :: budget :: seeds :: rest ->
    (* when each USB milestone first appeared, in total executions; "seeded" starts the corpus from
       one GET_DESCRIPTOR control transfer (no SET_ADDRESS in it) *)
    let t = target tname and (cfg, k, sync, fresh) = config cname in
    let corpus = if rest = [ "seeded" ] then [ usb_get_descriptor ] else [] in
    List.iter (fun seed ->
      let r = Hwfuzz.campaign ~cfg ~corpus ~k ~sync ~budget:(int_of_string budget) ~fresh ~seed:(int_of_string seed) t in
      let first p = List.fold_left (fun m (f, e) -> if p f then (match m with None -> Some e | Some x -> Some (min x e)) else m) None r.first_hit in
      let show = function None -> "-" | Some e -> string_of_int e in
      Printf.printf "%s %s seed %s: response %s ack %s nak %s stall %s data %s address %s configured %s VIOLATION %s | coverage %d queue %d\n%!"
        tname cname seed (show (first (fun f -> f >= 200 && f < 500))) (show (first (( = ) (200 + 0xD2))))
        (show (first (( = ) (200 + 0x5A)))) (show (first (( = ) (200 + 0x1E))))
        (show (first (fun f -> f = 200 + 0xC3 || f = 200 + 0x4B))) (show (first (fun f -> f >= 500 && f < 700)))
        (show (first (( = ) 700))) (show (first (( = ) 1))) r.coverage (Array.length r.queue))
      (String.split_on_char ',' seeds)
  | [ _; "cmin"; tname; budget ] ->
    let r = Hwfuzz.fuzz ~budget:(int_of_string budget) ~fresh:false ~seed:1 (target tname) in
    Printf.printf "%s: queue %d, minimised corpus %d, coverage %d\n" tname (Array.length r.queue)
      (List.length (Hwfuzz.cmin r.queue)) r.coverage
  | _ -> prerr_endline "usage: bench sweep TARGET CONFIG BUDGET SEEDS | bench cmin TARGET BUDGET"

(* the reused simulator must give exactly what a fresh one gives *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "resetcheck" ] ->
    List.iter (fun name ->
      let t = target name in
      let inst = Hwfuzz.instrument t in
      let fresh_t = { t with circuit = t.circuit } in
      let st = Random.State.make [| 7 |] in
      let inputs = List.init 20 (fun _ -> Hwfuzz.random_input st (Hwfuzz.record_bytes inst)) @ [ usb_session ] in
      let reused = List.map (fun s -> (Hwfuzz.execute t inst s).features |> List.sort compare) inputs in
      let rebuilt = List.map (fun s -> let i = Hwfuzz.instrument fresh_t in
                               let i = { i with resettable = false } in (Hwfuzz.execute fresh_t i s).features |> List.sort compare) inputs in
      Printf.printf "%s: resettable %b; reused and rebuilt simulators agree on %d of %d inputs\n" name inst.resettable
        (List.length (List.filter Fun.id (List.map2 ( = ) reused rebuilt))) (List.length inputs)) [ "lock4"; "packet"; "usb" ]
  | _ -> ()

let () =
  match Array.to_list Sys.argv with
  | [ _; "speed" ] ->
    let t = usb_target ~repair:true () in
    let inst = Hwfuzz.instrument t in
    Printf.printf "decision probes %d (%d bits), registers %d (%d bits), comparison operands %d (%d bits)\n"
      (Array.length inst.dec_widths) (Array.fold_left ( + ) 0 inst.dec_widths)
      (Array.length inst.reg_widths) (Array.fold_left ( + ) 0 inst.reg_widths)
      (Array.length inst.cmp_widths) (Array.fold_left ( + ) 0 inst.cmp_widths);
    let rows = usb_stream ~repair:true usb_session in
    let reps = 20 in
    let t0 = Unix.gettimeofday () in
    let sim = Cyclesim.create (Usb.Usb_dev.circuit ()) in
    let dp = Cyclesim.in_port sim "dp_in" and dm = Cyclesim.in_port sim "dm_in" in
    for _ = 1 to reps do
      Array.iter (fun ch -> List.iter (fun (n, v) -> (if n = "dp_in" then dp else dm) := Bits.of_int ~width:1 v) ch; Cyclesim.cycle sim) rows
    done;
    let t1 = Unix.gettimeofday () in
    for _ = 1 to reps do ignore (Hwfuzz.execute t inst usb_session) done;
    let t2 = Unix.gettimeofday () in
    let cyc = float (reps * Array.length rows) in
    Printf.printf "plain simulation %.0f cycles/s; instrumented execute %.0f cycles/s (one core)\n" (cyc /. (t1 -. t0)) (cyc /. (t2 -. t1))
  | _ -> ()

(* reproduce oracle violations: rerun a campaign, save queue entries whose run violates, and show
   what the device transmitted *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "usbviol"; tname; budget; seed ] ->
    let t = target tname in
    let r = Hwfuzz.campaign ~budget:(int_of_string budget) ~fresh:false ~seed:(int_of_string seed) t in
    let inst = Hwfuzz.instrument t in
    let n = ref 0 in
    Array.iter (fun (s, _) ->
      let res = Hwfuzz.execute t inst s in
      if List.mem 1 res.observed && !n < 5 then begin
        let path = Printf.sprintf "results-usb/violation_%s_%d.bin" tname !n in
        let oc = open_out_bin path in output_string oc s; close_out oc;
        Printf.printf "%s: %d bytes, %d cycles\n" path (String.length s) res.cycles;
        incr n
      end) r.queue;
    Printf.printf "%d violating queue entries saved\n" !n
  | _ -> ()

(* show an input as host packets, and every device transmission with its decoding *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "usbshow"; path ] ->
    let s = In_channel.with_open_bin path In_channel.input_all in
    let i = ref 1 and n = String.length s in
    while !i < n do
      let c = Char.code s.[!i] in
      let len = min (1 + (c land 15)) (n - !i - 1) in
      let bytes = List.init len (fun k -> Char.code s.[!i + 1 + k]) in
      i := !i + 1 + len;
      Printf.printf "host packet (repair %b, gap %d bits): %s\n" (c land 16 <> 0) (16 * (1 + (c lsr 5)))
        (String.concat " " (List.map (Printf.sprintf "%02x") bytes))
    done;
    let rows = usb_stream ~repair:true s in
    let sim = Cyclesim.create (Usb.Usb_dev.circuit ()) in
    let ip n = Cyclesim.in_port sim n and op n = Cyclesim.out_port sim n in
    ip "clear" := Bits.vdd; Cyclesim.cycle sim; ip "clear" := Bits.gnd;
    let seg = ref [] and start = ref 0 in
    Array.iteri (fun cyc ch ->
      List.iter (fun (nm, v) -> ip nm := Bits.of_int ~width:1 v) ch;
      Cyclesim.cycle sim;
      let oe = Bits.to_int !(op "oe") = 1 in
      if oe then begin
        if !seg = [] then start := cyc;
        seg := (match Bits.to_int !(op "dp_out"), Bits.to_int !(op "dm_out") with 1, 0 -> Usb.Host.J | 0, 1 -> K | _ -> SE0) :: !seg
      end else if !seg <> [] then begin
        let arr = Array.of_list (List.rev !seg) in
        seg := [];
        let line = String.concat "" (Array.to_list (Array.mapi (fun k l -> if k mod 4 = 2 then (match l with Usb.Host.J -> "J" | K -> "K" | SE0 -> "0") else "") arr)) in
        let first_k = let rec f i = if i >= Array.length arr then -1 else if arr.(i) = Usb.Host.K then i else f (i + 1) in f 0 in
        Printf.printf "device transmits at cycle %d for %d cycles: %s\n  decoded: %s\n" !start (Array.length arr) line
          (match (if first_k < 0 then None else Usb.Host.decode arr first_k) with
           | None -> "UNDECODABLE" | Some b -> String.concat " " (List.map (Printf.sprintf "%02x") b))
      end) rows;
    if !seg <> [] then Printf.printf "input ends at cycle %d while the device is still transmitting (%d cycles in, started %d)\n"
        (Array.length rows) (List.length !seg) !start
  | _ -> ()

(* Ethernet: check the target on unperturbed frames, then fuzz and save each kind of disagreement *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "ethcheck" ] ->
    let inst = Hwfuzz.instrument eth_target in
    List.iter (fun (name, s) ->
      let r = Hwfuzz.execute eth_target inst s in
      Printf.printf "%s: observed %s\n" name (String.concat "," (List.map string_of_int (List.sort compare r.observed))))
      [ ("clean 20-byte frame", "\000\019" ^ String.init 20 (fun i -> Char.chr (i * 37 land 255)));
        ("clean 64-byte frame", "\000\063" ^ String.init 64 (fun i -> Char.chr (i * 11 land 255)));
        ("glitch mid-frame", "\000\019" ^ String.init 20 (fun i -> Char.chr (i * 37 land 255)) ^ "\003\000\002") ]
  | [ _; "ethfuzz"; budget; seed ] ->
    let r = Hwfuzz.campaign ~budget:(int_of_string budget) ~fresh:false ~seed:(int_of_string seed) eth_target in
    List.iter (fun (f, e) -> Printf.printf "verdict %d first at %d executions\n" f e) (List.sort compare r.first_hit);
    let inst = Hwfuzz.instrument eth_target in
    let saved = Hashtbl.create 4 in
    Array.iter (fun (s, _) ->
      let res = Hwfuzz.execute eth_target inst s in
      List.iter (fun v -> if v < 10 && not (Hashtbl.mem saved v) then begin
        Hashtbl.replace saved v ();
        let path = Printf.sprintf "results-eth/verdict%d_seed%s.bin" v seed in
        Out_channel.with_open_bin path (fun oc -> output_string oc s);
        Printf.printf "saved %s (%d bytes)\n" path (String.length s) end) res.observed) r.queue;
    Printf.printf "coverage %d queue %d\n" r.coverage (Array.length r.queue)
  | _ -> ()

(* minimise an Ethernet reproducer for one verdict, then explain it *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "ethshow"; path; verdict ] ->
    let v = int_of_string verdict in
    let inst = Hwfuzz.instrument eth_target in
    let holds s = List.mem v (Hwfuzz.execute eth_target inst s).observed in
    let s0 = In_channel.with_open_bin path In_channel.input_all in
    assert (holds s0);
    let parse s =
      let n = String.length s in
      let len = 1 + Char.code s.[1] mod 64 in
      let payload = String.sub s 2 (min len (n - 2)) in
      let recs = List.init (max 0 ((n - 2 - len) / 3)) (fun k -> String.sub s (2 + len + 3 * k) 3) in
      (len, payload, recs) in
    let build (len, payload, recs) = "\000" ^ String.make 1 (Char.chr (len - 1)) ^ payload ^ String.concat "" recs in
    (* drop perturbations one at a time, then shorten the payload, while the verdict holds *)
    let cur = ref (parse s0) in
    let changed = ref true in
    while !changed do
      changed := false;
      let (len, payload, recs) = !cur in
      List.iteri (fun k _ ->
        if not !changed then begin
          let c = (len, payload, List.filteri (fun j _ -> j <> k) recs) in
          if holds (build c) then (cur := c; changed := true)
        end) recs;
      if not !changed && len > 1 then begin
        let c = (len - 1, String.sub payload 0 (len - 1), recs) in
        if holds (build c) then (cur := c; changed := true)
      end
    done;
    let (len, payload, recs) = !cur in
    let s = build !cur in
    Out_channel.with_open_bin (Filename.remove_extension path ^ "_min.bin") (fun oc -> output_string oc s);
    let sent = List.init len (fun k -> Char.code payload.[k]) in
    let m = List.length (Eth.Eth_model.encode_frame ~h:eth_h sent) in
    Printf.printf "verdict %d, minimised: payload %d bytes, %d perturbation(s)\n" v len (List.length recs);
    List.iter (fun r ->
      let pos = ((Char.code r.[0] lsl 8) lor Char.code r.[1]) mod m and kind = Char.code r.[2] in
      let bit = pos / (2 * eth_h) and within = pos mod (2 * eth_h) in
      Printf.printf "  %s at sample %d = bit %d (%s), cycle %d of the bit\n"
        (match kind land 7 with 0 -> "edge one cycle late" | 1 -> "edge one cycle early" | 2 -> "one-cycle glitch"
                          | 3 -> Printf.sprintf "line near zero (comparator holds) for %d cycles" (1 + (kind lsr 3) land 3)
                          | _ -> Printf.sprintf "squelch off (polarity visible) for %d cycles" (1 + (kind lsr 3) land 3))
        pos bit (if bit < 64 then "preamble/SFD" else Printf.sprintf "frame byte %d" ((bit - 64) / 8)) within) recs;
    let res = Hwfuzz.execute eth_target inst s in
    let _, smp = !(Domain.DLS.get eth_truth) in
    let model = Eth.Eth_model.decode ~h:eth_h smp in
    Printf.printf "  model decodes %d frame(s): %s\n" (List.length model)
      (String.concat "; " (List.map (fun f -> Printf.sprintf "%d bytes%s" (List.length f)
                                        (if f = sent @ Eth.Eth_model.fcs_bytes sent then " (the sent frame)" else "")) model));
    Printf.printf "  observed verdicts %s\n" (String.concat "," (List.map string_of_int (List.sort compare res.observed)))
  | _ -> ()

(* the receiver's recovered bits, against the bits sent, for one reproducer *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "ethtrace"; path ] ->
    let s = In_channel.with_open_bin path In_channel.input_all in
    let rows = eth_stream s in
    let truth, _ = !(Domain.DLS.get eth_truth) in
    let sent_bits = List.concat_map Eth.Eth_model.bits_of_byte (List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ truth) in
    let c =
      let open Signal in
      let clock = input "clock" 1 and clear = input "clear" 1 and rx = input "rx" 1 and rx_active = input "rx_active" 1 in
      let _, bv, fe, ok, bit, bitv = Eth.Eth_rx.create ~clock ~clear ~h:eth_h ~rx ~rx_active in
      Circuit.create_exn ~name:"eth_rx_trace" [ output "bv" bv; output "fe" fe; output "ok" ok; output "bit" bit; output "bitv" bitv ] in
    let sim = Cyclesim.create c in
    let ip n = Cyclesim.in_port sim n and op n = Bits.to_int !(Cyclesim.out_port sim n) in
    ip "clear" := Bits.vdd; Cyclesim.cycle sim; ip "clear" := Bits.gnd;
    let got = Buffer.create 256 in
    Array.iteri (fun cyc ch ->
      List.iter (fun (nm, v) -> ip nm := Bits.of_int ~width:1 v) ch;
      Cyclesim.cycle sim;
      if op "bitv" = 1 then Buffer.add_char got (if op "bit" = 1 then '1' else '0');
      if op "fe" = 1 then Buffer.add_string got (Printf.sprintf " |end at cycle %d crc_ok=%d| " cyc (op "ok"))) rows;
    Printf.printf "sent: %s\n" (String.concat "" (List.map string_of_int (List.filteri (fun i _ -> i < 96) sent_bits)));
    Printf.printf "rtl:  %s\n" (Buffer.contents got)
  | _ -> ()

let () =
  match Array.to_list Sys.argv with
  | "ethverdict" :: _ :: files | _ :: "ethverdict" :: files ->
    let inst = Hwfuzz.instrument eth_target in
    List.iter (fun f ->
      let s = In_channel.with_open_bin f In_channel.input_all in
      let r = Hwfuzz.execute eth_target inst s in
      Printf.printf "%s: verdicts %s\n" f (String.concat "," (List.map string_of_int (List.sort compare r.observed)))) files
  | _ -> ()

(* is SET_ADDRESS reachable from the seed by editing only the setup bytes? *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "usbsetaddr" ] ->
    let pkt ?(gap = 1) bytes =
      String.make 1 (Char.chr (((List.length bytes - 1) land 15) lor 16 lor (gap lsl 5)))
      ^ String.concat "" (List.map (fun b -> String.make 1 (Char.chr b)) bytes) in
    let set_addr = "\000" ^ pkt [ 0x2D; 0; 0 ] ^ pkt ~gap:2 [ 0xC3; 0x00; 0x05; 0x05; 0x00; 0x00; 0x00; 0x00; 0x00 ]
                   ^ pkt ~gap:3 [ 0x69; 0; 0 ] ^ pkt ~gap:1 [ 0xD2 ] in
    let then_in = set_addr ^ pkt ~gap:3 [ 0x69; 5; 0 ] in
    List.iter (fun (name, t, s) ->
      let inst = Hwfuzz.instrument t in
      let r = Hwfuzz.execute t inst s in
      Printf.printf "%s: observed %s\n" name
        (String.concat " " (List.map (fun f -> if f >= 700 then "configured" else if f >= 500 then Printf.sprintf "addr=%d" (f - 500)
                                                else if f >= 200 then Printf.sprintf "pid=%02x" (f - 200) else "VIOLATION") (List.sort compare r.observed))))
      [ ("SET_ADDRESS(5) as edited seed, real device", usb_target ~repair:true (), set_addr);
        ("same plus IN to address 5, real device", usb_target ~repair:true (), then_in);
        ("same plus IN to address 5, planted fault", usb_target ~faulty:true ~repair:true (), then_in) ]
  | _ -> ()
