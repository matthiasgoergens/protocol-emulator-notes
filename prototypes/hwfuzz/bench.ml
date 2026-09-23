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
    finish = (fun () -> if !in_tx then check (); Hashtbl.fold (fun k () acc -> k :: acc) fs []) }

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

let usb_target ?(faulty = false) ~repair () =
  { Hwfuzz.name = "usb"; circuit = (if faulty then usb_faulty else Usb.Usb_dev.circuit); clock = "clock"; clear = Some "clear";
    max_cycles = 16_000; observer = Some usb_observer; stream = Some (usb_stream ~repair) }

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

let target name =
  let circuit, max_cycles = match name with
    | "lock4" -> lock 4, 256 | "lock8" -> lock 8, 256 | "packet" -> packet, 512
    | "usb" | "usb-raw" | "usb-faulty" -> Usb.Usb_dev.circuit, 0 | _ -> failwith ("unknown target " ^ name) in
  if name = "usb" then usb_target ~repair:true () else
  if name = "usb-raw" then usb_target ~repair:false () else
  if name = "usb-faulty" then usb_target ~faulty:true ~repair:true () else
  { Hwfuzz.name; circuit; clock = "clock"; clear = Some "clear"; max_cycles; observer = Some goal; stream = None }

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
  | [ _; "usbfuzz"; tname; cname; budget; seeds ] ->
    (* when each USB milestone first appeared, in total executions *)
    let t = target tname and (cfg, k, sync, fresh) = config cname in
    List.iter (fun seed ->
      let r = Hwfuzz.campaign ~cfg ~k ~sync ~budget:(int_of_string budget) ~fresh ~seed:(int_of_string seed) t in
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
