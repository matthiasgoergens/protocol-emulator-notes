(* Command-line side of the FPGA test bench.

     fpga_tests.exe manifest                 all tests as JSON (programme images, configuration)
     fpga_tests.exe predict NAME             the OCaml prediction of the run, in the trace format
     fpga_tests.exe check NAME --trace F [--capture F] [--mode sim|board] [--build plain|mp]
     fpga_tests.exe vcd TRACE [--quarter-ps N]   the trace as VCD on a quarter-clock time base

   A trace file is what emu_core's 'T' command returned, as text: a header line
   "N ovf trunc" and then one line per entry
   "cycle pin_in pin_out pin_oe flags host_out host_in pin_sub pin_in4" in hex. pin_sub and pin_in4
   hold four quarters per pin (bit 4i+p = pin i, quarter p). A capture file is one line per
   sampler word, "count data" in hex.

   --build says which bitstream produced the trace: plain (pads on the clock grid, pin_in4 is each
   pin's one sample repeated) or mp (pins 0 and 1 through the four-phase stage, whose samplers
   feed pin_in4). It changes the board model, not the replay.

   check applies three independent judgements:
   1. Replay. The captured inputs of every cycle (pins as the core saw them after the
      synchroniser, host bytes) are fed to the ISA interpreter (Isa.step, the executable
      specification), and its outputs must equal the captured outputs on every cycle. This is the
      lockstep test of deadline-sequencer/main.ml, with the FPGA in place of Cyclesim.
   2. Prediction. The interpreter runs free against Env, the model of the board. In simulation
      the whole trace must match exactly (it proves the C++ board models, the OCaml models and the
      RTL agree). On the board the devices are real, so the input timing may differ; outputs must
      still match exactly for tests whose outputs do not depend on input timing.
   3. Protocol. Independent decoders (deadline-sequencer/decoders.ml) read the pin levels and
      must recover the expected bytes, and the host bytes must be the expected ones. *)

open Programs

let find name =
  match List.find_opt (fun t -> t.name = name) (all ()) with
  | Some t -> t
  | None -> Printf.eprintf "unknown test %s\n" name; exit 2

(* ------------------------------------------------------------------ per-cycle records *)
type cyc = { pin_in : int; pin_out : int; pin_oe : int; flags : int; host_out : int; host_in : int;
             pin_sub : int; pin_in4 : int }
let zero_cyc = { pin_in = 0; pin_out = 0; pin_oe = 0; flags = 0; host_out = 0; host_in = 0; pin_sub = 0; pin_in4 = 0 }
let qbit v i p = (v lsr (4 * i + p)) land 1

let hov c = c.flags land 1 = 1 and hir c = c.flags land 2 = 2 and hiv c = c.flags land 4 = 4

(* The OCaml prediction: interpreter plus board model, cycle by cycle, as emu_core.v runs it.
   Outputs visible in cycle c (pin_out, pin_oe, pin_sub) are the state after step c-1; pins seen
   in cycle c are the raw levels of cycle c-2 (two-flop synchroniser), and before the run the core
   sat in clear with every output 0.

   In the four-phase build (`Mp), pins 0 and 1 reach their pads through the stage: during clock k
   the pad shows, in quarter p, quarter p of the pin_sub visible in cycle k-1, if the output
   enable visible in k-1 was set (else the pull-up). The stage's sampler on phase p takes the level
   of the quarter before p (in clock k: quarter p-1, and for p = 0 quarter 3 of clock k-1), and
   the core sees clock k's four samples in cycle k+2, as pin_in4. The phase-0 synchroniser samples
   the pad in quarter 3. Every other pin, and every pin in the plain build, has pin_in4 = its one
   sample repeated four times. *)
let predict ?(build = `Plain) t =
  let env = Env.create ~ctrl:t.ctrl ~wiring:t.wiring in
  let st = Isa.init () in
  let routed = Env.routed_mask t.ctrl in
  let n = t.cycles in
  let vis_sub = Array.make (max n 1) 0 and vis_oe = Array.make (max n 1) 0 in
  let get a c = if c < 0 then 0 else a.(c) in
  let pad01 k p =
    let oe = get vis_oe (k - 1) land lnot routed and sub = get vis_sub (k - 1) in
    let b i = if (oe lsr i) land 1 = 1 then qbit sub i p else 1 in
    b 0 lor (b 1 lsl 1) in
  let mp = build = `Mp in
  let mp01 k = if mp then Some ((get vis_oe (k - 1) land lnot routed) land 3, pad01 k 3) else None in
  let idle = if mp then Some (0, 3) else None in
  let r0 = Env.step ?mp01:idle env ~pin_out:0 ~pin_oe:0 in
  let raw_hist = [| r0; Env.step ?mp01:idle env ~pin_out:0 ~pin_oe:0 |] in
  let hq = Queue.of_seq (List.to_seq t.host_in) in
  let last_hin = ref 0 in
  let host_out_reg = ref 0 and vis_hov = ref false in
  let out = Array.make n zero_cyc in
  for c = 0 to n - 1 do
    vis_sub.(c) <- st.pin_sub; vis_oe.(c) <- st.pin_oe;
    let vis_out = st.pin_out in
    let pin_in = raw_hist.(0) in
    let raw = Env.step ?mp01:(mp01 c) env ~pin_out:st.pin_out ~pin_oe:st.pin_oe in
    raw_hist.(0) <- raw_hist.(1); raw_hist.(1) <- raw;
    let pin_in4 =
      let base = Isa.replicate4 pin_in in
      if not mp then base
      else begin
        let nib i =
          let smp p = if p = 0 then (pad01 (c - 3) 3 lsr i) land 1 else (pad01 (c - 2) (p - 1) lsr i) land 1 in
          smp 0 lor (smp 1 lsl 1) lor (smp 2 lsl 2) lor (smp 3 lsl 3) in
        (base land lnot 0xFF) lor nib 0 lor (nib 1 lsl 4)
      end in
    let valid = not (Queue.is_empty hq) in
    let hin = if valid then Queue.peek hq else !last_hin in
    let eff = Isa.step ~pin_in4 st ~mem:t.mem ~pin_in ~host_in:hin ~host_in_valid:valid in
    if eff.host_in_ready then (last_hin := Queue.pop hq; ());
    let flags = (if !vis_hov then 1 else 0) lor (if eff.host_in_ready then 2 else 0) lor (if valid then 4 else 0) in
    out.(c) <- { pin_in; pin_out = vis_out; pin_oe = vis_oe.(c); flags; host_out = !host_out_reg; host_in = hin;
                 pin_sub = vis_sub.(c); pin_in4 };
    (match eff.host_out with Some b -> host_out_reg := b; vis_hov := true | None -> vis_hov := false)
  done;
  out, env

(* ------------------------------------------------------------------ trace files *)
let read_lines f =
  let ic = open_in f in
  let rec go acc = match input_line ic with l -> go (l :: acc) | exception End_of_file -> close_in ic; List.rev acc in
  go []

let hex s = int_of_string ("0x" ^ s)
let words l = String.split_on_char ' ' (String.trim l) |> List.filter (( <> ) "")

(* returns (n, valid_until, per-cycle array up to valid_until) *)
let load_trace f =
  match read_lines f with
  | [] -> failwith "empty trace file"
  | hdr :: rest ->
    let n, ovf, trunc = match words hdr with [ a; b; c ] -> (int_of_string a, int_of_string b, int_of_string c) | _ -> failwith "bad header" in
    let entries = List.filter_map (fun l -> match words l with
        | [ c; a; b; d; e; g; h; u; v ] ->
          Some (hex c, { pin_in = hex a; pin_out = hex b; pin_oe = hex d; flags = hex e; host_out = hex g; host_in = hex h;
                         pin_sub = hex u; pin_in4 = hex v })
        | [] -> None | _ -> failwith ("bad trace line: " ^ l)) rest in
    let until = if ovf <> 0 then trunc else n in
    let arr = Array.make until zero_cyc in
    (match entries with (0, _) :: _ -> () | _ -> failwith "trace does not start at cycle 0");
    let rec fill = function
      | (c, e) :: ((c2, _) :: _ as more) -> for i = c to min (c2 - 1) (until - 1) do arr.(i) <- e done; fill more
      | [ (c, e) ] -> for i = c to until - 1 do arr.(i) <- e done
      | [] -> () in
    fill entries;
    n, until, (ovf <> 0), arr

let write_trace oc (arr : cyc array) =
  Printf.fprintf oc "%d 0 0\n" (Array.length arr);
  Array.iteri (fun c e ->
    let changed = c = 0 || arr.(c - 1) <> e in
    if changed then Printf.fprintf oc "%x %02x %02x %02x %02x %02x %02x %08x %08x\n" c e.pin_in e.pin_out e.pin_oe e.flags
        e.host_out e.host_in e.pin_sub e.pin_in4) arr

(* ------------------------------------------------------------------ checks *)
let results = ref []
let verdict name ok detail =
  results := (name, ok) :: !results;
  Printf.printf "  %-28s %s  %s\n" name (if ok then "PASS" else "FAIL") detail

let info fmt = Printf.printf ("  " ^^ fmt ^^ "\n")

let replay t (arr : cyc array) =
  let st = Isa.init () in
  let mism = ref 0 and first = ref None in
  let n = Array.length arr in
  let bad c what = incr mism; if !first = None then first := Some (c, what) in
  if n > 0 && (arr.(0).pin_out <> 0 || arr.(0).pin_oe <> 0 || arr.(0).pin_sub <> 0 || hov arr.(0)) then bad 0 "outputs not at reset in cycle 0";
  let sub_diff a b =
    let r = ref "" in
    for i = 7 downto 0 do for p = 3 downto 0 do
      if qbit a i p <> qbit b i p then r := Printf.sprintf "pin %d quarter %d: fpga %d interp %d" i p (qbit a i p) (qbit b i p)
    done done; !r in
  for c = 0 to n - 2 do
    let x = arr.(c) and y = arr.(c + 1) in
    let eff = Isa.step ~pin_in4:x.pin_in4 st ~mem:t.mem ~pin_in:x.pin_in ~host_in:x.host_in ~host_in_valid:(hiv x) in
    if st.pin_out <> y.pin_out then bad (c + 1) (Printf.sprintf "pin_out fpga %02x interp %02x" y.pin_out st.pin_out)
    else if st.pin_sub <> y.pin_sub then bad (c + 1) ("pin_sub " ^ sub_diff y.pin_sub st.pin_sub)
    else if st.pin_oe <> y.pin_oe then bad (c + 1) (Printf.sprintf "pin_oe fpga %02x interp %02x" y.pin_oe st.pin_oe)
    else if eff.host_in_ready <> hir x then bad c "host_in_ready"
    else match eff.host_out with
      | Some b when not (hov y && y.host_out = b) -> bad (c + 1) (Printf.sprintf "host_out: interp %02x" b)
      | None when hov y -> bad (c + 1) "host_out: fpga emitted, interp did not"
      | _ -> ()
  done;
  verdict "replay through interpreter" (!mism = 0)
    (match !first with
     | None -> Printf.sprintf "%d cycles, every output equal, pin_sub on all %d quarters" n (4 * n)
     | Some (c, w) -> Printf.sprintf "%d mismatching cycles, first at %d: %s" !mism c w)

let compare_prediction t ~mode ~build (arr : cyc array) =
  let pred, env = predict ~build t in
  let n = min (Array.length arr) (Array.length pred) in
  (* On the board the values of host bytes can come from real parts (a flash's ID, an ACK), which
     the model does not know; the replay checks those values exactly and the expectations judge
     them, so here the board is held to the pins and to when bytes are emitted. *)
  let outputs_eq a b = a.pin_out = b.pin_out && a.pin_oe = b.pin_oe && a.pin_sub = b.pin_sub && hov a = hov b in
  let full_eq a b = outputs_eq a b && (not (hov a) || a.host_out = b.host_out)
                    && a.pin_in = b.pin_in && a.pin_in4 = b.pin_in4 && a.flags = b.flags
                    && (not (hiv a) || a.host_in = b.host_in) in
  let first_diff eq =
    let r = ref None in
    for c = n - 1 downto 0 do if not (eq arr.(c) pred.(c)) then r := Some c done; !r in
  let show c = let a = arr.(c) and b = pred.(c) in
    Printf.sprintf "cycle %d: captured in=%02x out=%02x oe=%02x fl=%02x sub=%08x in4=%08x, predicted in=%02x out=%02x oe=%02x fl=%02x sub=%08x in4=%08x"
      c a.pin_in a.pin_out a.pin_oe a.flags a.pin_sub a.pin_in4 b.pin_in b.pin_out b.pin_oe b.flags b.pin_sub b.pin_in4 in
  (match mode with
   | `Sim ->
     let d = first_diff full_eq in
     verdict "prediction (whole trace)" (d = None)
       (match d with None -> Printf.sprintf "%d cycles identical to the OCaml board model" n | Some c -> show c)
   | `Board ->
     let d = first_diff outputs_eq in
     let din = first_diff full_eq in
     (match d with
      | None -> verdict "prediction (outputs)" true (Printf.sprintf "%d cycles of outputs identical" n)
      | Some c when t.board_only_lenient ->
        info "prediction (outputs): differs from %s (input timing of real parts; not a failure for this test)" (show c)
      | Some c -> verdict "prediction (outputs)" false (show c));
     (match din with None -> () | Some c -> info "inputs first differ from the board model at %s" (show c)));
  env

(* The quarter-clock timeline of pin i's pin_sub as recorded: level at quarter 4c+p. *)
let sub_timeline (arr : cyc array) i = Array.init (4 * Array.length arr) (fun t -> qbit arr.(t / 4).pin_sub i (t mod 4))

(* Loopback through the four-phase stage, judged from the trace alone (no interpreter, no board
   model): the pad of pin i in quarter p of clock k is quarter p of the pin_sub recorded in cycle
   k-1 when the recorded output enable of k-1 was set (else the pull-up), and the core sees the
   pad of quarter T - 9 as pin_in4 quarter T (T = 4c + p). [extra] is additional delay in
   quarters (pad and wiring delay on a real board). Returns (compared, mismatches). *)
let loopback_mismatch ~routed (arr : cyc array) i extra =
  let n = Array.length arr in
  let pad g = if g < 4 then 1 else
      let k = g / 4 and p = g mod 4 in
      let prev = arr.(k - 1) in
      if ((prev.pin_oe land lnot routed) lsr i) land 1 = 1 then qbit prev.pin_sub i p else 1 in
  let cmp = ref 0 and bad = ref 0 in
  for tq = 4 * 4 to 4 * n - 1 do
    let g = tq - 9 - extra in
    if g >= 4 then begin
      incr cmp;
      if qbit arr.(tq / 4).pin_in4 i (tq mod 4) <> pad g then incr bad
    end
  done;
  !cmp, !bad

let decode_checks t ~mode ~build (arr : cyc array) =
  let trace = Array.to_list (Array.mapi (fun c e -> { Decoders.c; bus = e.pin_in }) arr) in
  let host = Array.to_list arr |> List.filter hov |> List.map (fun e -> e.host_out) in
  let hexs l = String.concat " " (List.map (Printf.sprintf "%02x") l) in
  List.iter (function
    | Uart_on_pin { pin; bit_cycles; bytes } ->
      let d = Decoders.uart trace ~pin ~bit_cycles in
      let got = List.map (fun (_, b, ok) -> if ok then b else -1) d in
      verdict (Printf.sprintf "uart decode pin %d" pin) (got = bytes) (Printf.sprintf "got [%s] expected [%s]" (hexs got) (hexs bytes))
    | Host_bytes bytes -> verdict "host bytes" (host = bytes) (Printf.sprintf "got [%s] expected [%s]" (hexs host) (hexs bytes))
    | Host_bytes_one_of l ->
      verdict "host bytes (known ids)" (List.mem host l) (Printf.sprintf "got [%s]; known: %s" (hexs host) (String.concat ", " (List.map (fun b -> "[" ^ hexs b ^ "]") l)))
    | Spi_bytes { sclk; mosi; cs; bytes } ->
      let got = Decoders.spi trace ~sclk ~mosi ~cs in
      let pre = List.filteri (fun i _ -> i < List.length bytes) got in
      verdict "spi decode (mosi)" (pre = bytes) (Printf.sprintf "got [%s] expected prefix [%s]" (hexs got) (hexs bytes))
    | I2c_bytes { sda; scl; bytes; acks } ->
      let got, stopped = Decoders.i2c trace ~sda ~scl in
      let gb = List.map fst got and ga = List.map snd got in
      let acks_s = String.concat "" (List.map (fun a -> if a then "A" else "N") ga) in
      let ok = gb = bytes && stopped && (match acks with None -> true | Some a -> a = ga) in
      verdict "i2c decode" ok (Printf.sprintf "got [%s] acks %s stop=%b expected [%s]%s" (hexs gb) acks_s stopped (hexs bytes)
                                 (match acks with None -> "" | Some a -> " acks " ^ String.concat "" (List.map (fun a -> if a then "A" else "N") a)))
    | Host_bytes_by_build { plain; mp } ->
      let want = if build = `Mp then mp else plain in
      verdict "host bytes (quad samples)" (host = want)
        (Printf.sprintf "got [%s] expected [%s] for the %s build" (hexs host) (hexs want) (if build = `Mp then "four-phase" else "plain"))
    | Quarter_spacing { pin; spacing; min_edges } ->
      let tl = sub_timeline arr pin in
      let edges = ref [] in
      Array.iteri (fun tq v -> if tq > 0 && v <> tl.(tq - 1) then edges := tq :: !edges) tl;
      let e = Array.of_list (List.rev !edges) in
      let sp = Array.init (max 0 (Array.length e - 1)) (fun k -> e.(k + 1) - e.(k)) in
      let odd = Array.to_list sp |> List.filter (( <> ) spacing) in
      verdict (Printf.sprintf "pin_sub edges pin %d" pin) (Array.length e >= min_edges && odd = [])
        (Printf.sprintf "%d edges on the quarter grid, spacings all %d quarters: %b%s" (Array.length e) spacing (odd = [])
           (match odd with [] -> "" | d :: _ -> Printf.sprintf " (first other spacing %d)" d))
    | Quad_loopback { pins } ->
      if build <> `Mp then info "quad loopback: plain build, pads on the clock grid; not applicable"
      else begin
        let routed = Env.routed_mask t.ctrl in
        List.iter (fun i ->
          let cmp, bad0 = loopback_mismatch ~routed arr i 0 in
          match mode with
          | `Sim ->
            verdict (Printf.sprintf "quad loopback pin %d" i) (bad0 = 0 && cmp > 0)
              (Printf.sprintf "%d quarters: stage samples = recorded pin_sub through the stage, %d differ" cmp bad0)
          | `Board ->
            let best = List.init 9 (fun x -> x, snd (loopback_mismatch ~routed arr i x))
                       |> List.fold_left (fun (bx, bb) (x, b) -> if b < bb then (x, b) else (bx, bb)) (0, max_int) in
            verdict (Printf.sprintf "quad loopback pin %d" i) (snd best = 0)
              (Printf.sprintf "%d quarters; best extra delay %d quarters with %d mismatches (0 in simulation)" cmp (fst best) (snd best)))
          pins
      end
    | Capture_uart _ | Trace_overflows -> ()) t.expects

let capture_checks t capture =
  List.iter (function
    | Capture_uart bytes ->
      (match capture with
       | None -> verdict "sampler capture" false "no capture file"
       | Some f ->
         let words = List.filter_map (fun l -> match words l with [ c; d ] -> Some (hex c, hex d) | _ -> None) (read_lines f) in
         let frames = List.map (fun (cnt, w) -> let n = if cnt = 0 then 16 else cnt in List.init n (fun k -> (w lsr k) land 1)) words in
         let got = List.filter_map (function
             | 0 :: rest when List.length rest = 9 && List.nth rest 8 = 1 ->
               Some (List.fold_left (fun a i -> a lor (List.nth rest i lsl i)) 0 (List.init 8 Fun.id))
             | _ -> None) frames in
         let hexs l = String.concat " " (List.map (Printf.sprintf "%02x") l) in
         verdict "sampler capture decode" (got = bytes)
           (Printf.sprintf "%d words, got [%s] expected [%s]" (List.length words) (hexs got) (hexs bytes)))
    | _ -> ()) t.expects

let check name ~trace ~capture ~mode ~build =
  let t = find name in
  Printf.printf "== %s (%s, %s build)\n" t.name (match mode with `Sim -> "simulation" | `Board -> "board")
    (match build with `Mp -> "four-phase" | `Plain -> "plain");
  let n, until, ovf, arr = load_trace trace in
  if n <> t.cycles then info "note: run was %d cycles, test defines %d" n t.cycles;
  if ovf then info "trace buffer overflowed: checking cycles 0..%d only" (until - 1);
  replay t arr;
  let env = compare_prediction t ~mode ~build arr in
  decode_checks t ~mode ~build arr;
  capture_checks t capture;
  if List.mem Trace_overflows t.expects then
    verdict "trace overflow reported" ovf (Printf.sprintf "overflow %b, cycles checked %d of %d" ovf until n);
  (match t.forbid_flash_cmds_except with
   | Some allowed ->
     let cmds = List.rev env.Env.flash.commands in
     verdict "flash commands (model)" (List.for_all (fun c -> List.mem c allowed) cmds)
       (String.concat " " (List.map (Printf.sprintf "%02x") cmds))
   | None -> ());
  let ok = List.for_all snd !results in
  Printf.printf "RESULT %s %s\n" t.name (if ok then "PASS" else "FAIL");
  exit (if ok then 0 else 1)

(* ------------------------------------------------------------------ manifest *)
let json_list f l = "[" ^ String.concat "," (List.map f l) ^ "]"
let json_str s = "\"" ^ String.concat "\\\"" (String.split_on_char '"' s) ^ "\""

let manifest () =
  let tests = all () in
  let one t =
    let _, env = predict t in
    let flash_cmds = List.rev env.Env.flash.commands in
    let imem = Array.to_list (Array.concat (Array.to_list t.mem)) in
    Printf.sprintf "{\"name\":%s,\"doc\":%s,\"cycles\":%d,\"ctrl\":%d,\"cfg\":%s,\"host_in\":%s,\"stream\":%s,\"needs\":%s,\"wiring\":{\"jumper_0_7\":%b,\"header_i2c_slave\":%b,\"header_slave_addr\":%d,\"header_flash\":%b,\"rtc_addr\":%d},\"flash_allowed\":%s,\"flash_cmds_predicted\":%s,\"subslot\":%b,\"quad\":%b,\"imem\":%s}"
      (json_str t.name) (json_str t.doc) t.cycles t.ctrl
      (json_list (fun (r, v) -> Printf.sprintf "[%d,%d]" r v) t.cfg)
      (json_list string_of_int t.host_in)
      (json_list (fun (c, w) -> Printf.sprintf "[%d,%d]" c w) t.stream)
      (json_list json_str t.needs)
      t.wiring.jumper_0_7 t.wiring.header_i2c_slave t.wiring.header_slave_addr t.wiring.header_flash t.wiring.rtc_addr
      (match t.forbid_flash_cmds_except with None -> "null" | Some l -> json_list string_of_int l)
      (json_list string_of_int flash_cmds)
      (List.exists (function Quarter_spacing _ -> true | _ -> false) t.expects)
      (List.exists (function Quad_loopback _ | Host_bytes_by_build _ -> true | _ -> false) t.expects)
      (json_list string_of_int imem) in
  print_string ("[\n" ^ String.concat ",\n" (List.map one tests) ^ "\n]\n")

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ "manifest" ] -> manifest ()
  | [ "list" ] -> List.iter (fun t -> Printf.printf "%-14s %s\n" t.name t.doc) (all ())
  | [ "predict"; name ] -> let arr, _ = predict (find name) in write_trace stdout arr
  | [ "predict"; name; "--build"; "mp" ] -> let arr, _ = predict ~build:`Mp (find name) in write_trace stdout arr
  | "vcd" :: file :: rest ->
    let qps = match rest with [ "--quarter-ps"; n ] -> int_of_string n | _ -> 4167 in
    Vcd.write stdout ~quarter_ps:qps (let _, until, _, arr = load_trace file in ignore until;
                                      Array.map (fun c -> { Vcd.pin_in = c.pin_in; pin_out = c.pin_out; pin_oe = c.pin_oe;
                                                            flags = c.flags; host_out = c.host_out; pin_sub = c.pin_sub;
                                                            pin_in4 = c.pin_in4 }) arr)
  | "check" :: name :: rest ->
    let rec opts tr cap mode build = function
      | "--trace" :: f :: r -> opts (Some f) cap mode build r
      | "--capture" :: f :: r -> opts tr (Some f) mode build r
      | "--mode" :: "sim" :: r -> opts tr cap `Sim build r
      | "--mode" :: "board" :: r -> opts tr cap `Board build r
      | "--build" :: "plain" :: r -> opts tr cap mode `Plain r
      | "--build" :: "mp" :: r -> opts tr cap mode `Mp r
      | [] -> (tr, cap, mode, build)
      | x :: _ -> Printf.eprintf "bad option %s\n" x; exit 2 in
    let tr, cap, mode, build = opts None None `Sim `Plain rest in
    (match tr with None -> prerr_endline "check needs --trace"; exit 2 | Some trace -> check name ~trace ~capture:cap ~mode ~build)
  | _ -> prerr_endline "usage: fpga_tests.exe (manifest | list | predict NAME [--build mp] | vcd TRACE [--quarter-ps N] | check NAME --trace F [--capture F] [--mode sim|board] [--build plain|mp])"; exit 2
