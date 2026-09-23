(* Benchmarks for hwfuzz. Each target is an ordinary Hardcaml circuit; the fuzzer knows nothing
   about it beyond clock and clear names. *)
open Hardcaml

(* A combination lock: four strobed key bytes in order open it. Random inputs essentially never
   do (about 256^4 tries); coverage guidance should find the stepping stones. The state is not an
   output: the fuzzer has to find it through the circuit's own decisions and registers. *)
let lock () =
  let open Signal in
  let clock = input "clock" 1 and clear = input "clear" 1 in
  let data = input "data" 8 and strobe = input "strobe" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let keys = [ 0x4A; 0x53; 0x21; 0x7E ] in
  let state = wire 3 in
  let key = mux state (List.map (of_int ~width:8) keys @ [ zero 8 ]) in
  let next = mux2 (state ==:. 4) state (mux2 strobe (mux2 (data ==: key) (state +:. 1) (zero 3)) state) in
  state <== reg spec next;
  Circuit.create_exn ~name:"lock" [ output "open" (state ==:. 4) ]

(* the observer doubles as the oracle: feature 1 once the lock is open *)
let opened () =
  let hit = ref false in
  { Hwfuzz.observe = (fun ~cycle:_ get -> if get "open" = 1 then hit := true);
    finish = (fun () -> if !hit then [ 1 ] else []) }

let lock_target = { Hwfuzz.name = "lock"; circuit = lock; clock = "clock"; clear = Some "clear";
                    max_cycles = 256; observer = Some opened }

let () =
  match Array.to_list Sys.argv with
  | [ _; "lock"; budget; mode; seeds ] ->
    List.iter (fun seed ->
      let r = Hwfuzz.fuzz ~budget:(int_of_string budget) ~fresh:(mode = "random") ~seed:(int_of_string seed) lock_target in
      let hit = List.assoc_opt 1 r.first_hit in
      Printf.printf "lock %s seed %s: %s; coverage %d, queue %d, execs %d\n%!" mode seed
        (match hit with Some e -> Printf.sprintf "opened after %d execs" e | None -> "never opened")
        r.coverage (Array.length r.queue) r.execs;
      if mode <> "random" then
        Array.iteri (fun i n -> Printf.printf "  %-11s uses %6d  wins %4d\n" n r.stats.uses.(i) r.stats.wins.(i)) Hwfuzz.op_names)
      (String.split_on_char ',' seeds)
  | _ -> prerr_endline "usage: bench lock BUDGET fuzz|random SEEDS"

(* diagnosis: hand-made inputs with 0..4 correct key bytes *)
let () =
  match Array.to_list Sys.argv with
  | [ _; "lockdiag" ] ->
    let inst = Hwfuzz.instrument lock_target in
    Printf.printf "data ports: %s; decisions %d (widths %s); registers %d; record %d bytes\n"
      (String.concat "," (List.map (fun (n, w) -> Printf.sprintf "%s:%d" n w) inst.data_ports))
      (Array.length inst.dec_widths) (String.concat "," (Array.to_list (Array.map string_of_int inst.dec_widths)))
      (Array.length inst.reg_widths) (Hwfuzz.record_bytes inst);
    let keys = [ 0x4A; 0x53; 0x21; 0x7E ] in
    let prev = ref [] in
    for k = 0 to 4 do
      let recs = List.filteri (fun i _ -> i < k) keys in
      let s = "\000" ^ String.concat "" (List.map (fun b -> String.init 3 (fun i -> Char.chr [| 0; b; 1 |].(i))) recs)
              ^ String.init 3 (fun i -> Char.chr [| 0; 0; 0 |].(i)) in
      let r = Hwfuzz.execute lock_target inst s in
      let fresh = List.filter (fun f -> not (List.mem f !prev)) r.features in
      Printf.printf "%d correct keys: %d features, %d new vs previous, observed %s, cycles %d\n" k
        (List.length r.features) (List.length fresh) (String.concat "," (List.map string_of_int r.observed)) r.cycles;
      prev := r.features
    done
  | _ -> ()

(* software copy of the lock driven the way Hwfuzz.execute drives it: the highest state reached *)
let lock_depth (s : string) =
  let keys = [| 0x4A; 0x53; 0x21; 0x7E |] in
  let mask = if String.length s > 0 then Char.code s.[0] else 0 in
  let st = ref 0 and best = ref 0 and cycles = ref 1 in
  (try
     for r = 0 to (String.length s - 1) / 3 - 1 do
       let hb = Char.code s.[1 + 3 * r] in
       let hold = if hb < 192 then 1 + (hb land 3) else 1 lsl (hb land 15) in
       let data = if mask land 1 <> 0 then 0 else Char.code s.[2 + 3 * r] in
       let strobe = if mask land 2 <> 0 then 0 else Char.code s.[3 + 3 * r] land 1 in
       for _ = 1 to hold do
         if !cycles >= 256 then raise Exit;
         incr cycles;
         if !st < 4 && strobe = 1 then st := (if data = keys.(!st) then !st + 1 else 0);
         best := max !best !st
       done
     done
   with Exit -> ());
  !best

let () =
  match Array.to_list Sys.argv with
  | [ _; "lockdepth"; budget; seed ] ->
    let r = Hwfuzz.fuzz ~budget:(int_of_string budget) ~fresh:false ~seed:(int_of_string seed) lock_target in
    let h = Array.make 5 0 in
    Array.iter (fun (s, _) -> let d = lock_depth s in h.(d) <- h.(d) + 1) r.queue;
    Printf.printf "queue %d; entries by deepest lock state reached: %s\n" (Array.length r.queue)
      (String.concat " " (Array.to_list (Array.mapi (fun i c -> Printf.sprintf "%d:%d" i c) h)));
    (* the deepest entries, record by record: hold byte, data, strobe *)
    let deepest = Array.fold_left (fun m (s, _) -> max m (lock_depth s)) 0 r.queue in
    Array.iter (fun (s, _) -> if lock_depth s = deepest then begin
      Printf.printf "depth %d, mask %d:" deepest (Char.code s.[0]);
      for i = 0 to (String.length s - 1) / 3 - 1 do
        Printf.printf " [h%d %02x s%d]" (Char.code s.[1 + 3 * i]) (Char.code s.[2 + 3 * i]) (Char.code s.[3 + 3 * i] land 1) done;
      print_newline () end) r.queue
  | _ -> ()
