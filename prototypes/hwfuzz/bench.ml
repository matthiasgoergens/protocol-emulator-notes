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

let target name =
  let circuit, max_cycles = match name with
    | "lock4" -> lock 4, 256 | "lock8" -> lock 8, 256 | "packet" -> packet, 512
    | _ -> failwith ("unknown target " ^ name) in
  { Hwfuzz.name; circuit; clock = "clock"; clear = Some "clear"; max_cycles; observer = Some goal }

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
  | [ _; "cmin"; tname; budget ] ->
    let r = Hwfuzz.fuzz ~budget:(int_of_string budget) ~fresh:false ~seed:1 (target tname) in
    Printf.printf "%s: queue %d, minimised corpus %d, coverage %d\n" tname (Array.length r.queue)
      (List.length (Hwfuzz.cmin r.queue)) r.coverage
  | _ -> prerr_endline "usage: bench sweep TARGET CONFIG BUDGET SEEDS | bench cmin TARGET BUDGET"
