(* A miter of the RTL core (sequencer2.ml, optionally with one of its planted bugs) and the
   specification circuit (spec_core.ml), for Yosys. Every input is free on every clock: the
   instruction word (so the check covers every programme, even one that changes under the core's
   feet), pins, host, ports, flags, host control, and the bank's read data. The first clock
   clears both; from the second on, [mismatch] rises if any output or any architectural register
   differs, compared as the lockstep test compares them (lockstep2.ml, harness2.ml): data outputs
   only while their valid strobe is set, and the accumulator of a thread whose LDB byte is still
   on its way from the SRAM replaced by that byte.

   Usage: miter.exe FILE [BUG]     BUG: a description from Sequencer2.bugs, e.g. "WAITC 9 inverted"
          miter.exe --list           the descriptions
          miter.exe --sim N [BUG]    N random clocks in Cyclesim (a smoke test of the miter)
          miter.exe --decode LOG     a Yosys counterexample as a programme trace *)
open Hardcaml
open Signal

let circuit ?bug () =
  let clock = input "clock" 1 in
  let i name w = input name w in
  let imem_data = i "imem_data" 16 and pin_in = i "pin_in" 8 and pin_in4 = i "pin_in4" 32 in
  let host_in = i "host_in" 8 and host_in_valid = i "host_in_valid" 1 in
  let port_in = Array.init 4 (fun k -> i (Printf.sprintf "port_in%d" k) 8) in
  let port_in_valid = i "port_in_valid" 4 and port_out_ready = i "port_out_ready" 4 and flags = i "flags" 16 in
  let ctl_valid = i "ctl_valid" 1 and ctl_thread = i "ctl_thread" 2 and ctl_page = i "ctl_page" 2 and ctl_pc = i "ctl_pc" 8 in
  let boot_page = i "boot_page" 8 and boot_pc = i "boot_pc" 32 and rd = i "bank_rd" 8 in
  let spec = Reg_spec.create ~clock () in
  (* every register starts at 0 (Yosys -set-init-zero): the first clock clears the cores *)
  let started = reg spec vdd in
  let clear = ~:started in
  let rd_reg = reg spec rd in       (* the SRAM's output: the byte read in the previous clock *)
  let r = Sequencer2.create ?bug ~clock ~clear ~imem_data ~pin_in ~pin_in4 ~host_in ~host_in_valid ~port_in
      ~port_in_valid ~port_out_ready ~flags ~ctl_valid ~ctl_thread ~ctl_page ~ctl_pc ~boot_page ~boot_pc
      ~bank_rdata:rd_reg () in
  let s = Spec_core.create ~clock ~clear ~imem_data ~pin_in ~pin_in4 ~host_in ~host_in_valid ~port_in
      ~port_in_valid ~port_out_ready ~flags ~ctl_valid ~ctl_thread ~ctl_page ~ctl_pc ~boot_page ~boot_pc ~bank_rd:rd in
  let dbg name = List.assoc name r.dbg in
  let field name w t = select (dbg name) (w * t + w - 1) (w * t) in
  let pend = dbg "dbg_pend" in
  let rtl_acc t = mux2 (bit pend 2 &: (select pend 1 0 ==:. t)) rd_reg (field "dbg_acc" 8 t) in
  let per name w (arr : Signal.t array) = List.init Isa2.n_threads (fun t -> (Printf.sprintf "%s%d" name t, field name w t <>: arr.(t))) in
  let when_ v x = v &: x in
  let diffs =
    [ "imem_addr", r.imem_addr <>: s.imem_addr;
      "pin_out", r.pin_out <>: s.pin_out; "pin_oe", r.pin_oe <>: s.pin_oe; "pin_sub", r.pin_sub <>: s.pin_sub;
      "host_out_valid", r.host_out_valid <>: s.host_out_valid;
      "host_out", when_ s.host_out_valid ((r.host_out <>: s.host_out) |: (r.host_tag <>: s.host_tag));
      "host_in_ready", r.host_in_ready <>: s.host_in_ready;
      "port_out_valid", r.port_out_valid <>: s.port_out_valid;
      "port_out_data", when_ (s.port_out_valid <>:. 0) (r.port_out_data <>: s.port_out_data);
      "port_in_ready", r.port_in_ready <>: s.port_in_ready;
      "bank_we", r.bank_we <>: s.bank_we; "bank_re", r.bank_re <>: s.bank_re;
      "bank_addr", when_ (s.bank_we |: s.bank_re) (r.bank_addr <>: s.bank_addr);
      "bank_wdata", when_ s.bank_we (r.bank_wdata <>: s.bank_wdata);
      "fine_valid", r.fine_valid <>: s.fine_valid; "fine_out", when_ s.fine_valid (r.fine_out <>: s.fine_out);
      "cfg_out", r.cfg_out <>: s.cfg_out;
      "thread", dbg "dbg_thread" <>: s.thread; "latch", dbg "dbg_latch" <>: s.state.latch ]
    @ List.init Isa2.n_threads (fun t -> (Printf.sprintf "acc%d" t, rtl_acc t <>: s.state.accs.(t)))
    @ per "dbg_pc" 8 s.state.pcs @ per "dbg_page" 2 s.state.pages @ per "dbg_cnt" 12 s.state.cnts
    @ per "dbg_dl" 12 s.state.dls @ per "dbg_bp" 10 s.state.bps @ per "dbg_fine" 8 s.state.fines
    @ per "dbg_armed" 1 s.state.armed @ per "dbg_cfg" 8 s.state.cfgs @ per "dbg_lsend" 3 s.state.lsend
    @ per "dbg_inbox" 8 s.state.inbox @ per "dbg_full" 1 s.state.full in
  let mismatch = started &: reduce ~f:( |: ) (List.map snd diffs) in
  Circuit.create_exn ~name:"miter"
    (output "mismatch" mismatch :: List.map (fun (n, d) -> output ("diff_" ^ n) (started &: d)) diffs)

(* the miter in Cyclesim with random inputs: a smoke test of the miter itself before Yosys sees
   it (clean RTL: no mismatch; a planted bug: a mismatch, usually soon) *)
let simulate ?bug ~cycles ~seed () =
  Random.init seed;
  let sim = Cyclesim.create (circuit ?bug ()) in
  let first = ref None and per_diff = Hashtbl.create 16 in
  let diff_ports = List.filter_map (fun (n, r) -> if String.length n > 5 && String.sub n 0 5 = "diff_" then Some (n, r) else None)
      (Cyclesim.outputs sim) in
  for c = 0 to cycles - 1 do
    List.iter (fun (_, r) ->
        let w = Bits.width !r in
        r := Bits.of_int ~width:w (Random.bits () land ((1 lsl (min w 30)) - 1) lor (if w > 30 then (Random.bits () lsl 30) land ((1 lsl (min w 60)) - 1) else 0)))
      (Cyclesim.inputs sim);
    (* host control rarely, as the lockstep test does *)
    Cyclesim.in_port sim "ctl_valid" := Bits.of_int ~width:1 (if Random.int 250 = 0 then 1 else 0);
    Cyclesim.cycle sim;
    if Bits.to_int !(Cyclesim.out_port sim "mismatch") = 1 then begin
      if !first = None then first := Some c;
      List.iter (fun (n, r) -> if Bits.to_int !r = 1 then Hashtbl.replace per_diff n (1 + Option.value (Hashtbl.find_opt per_diff n) ~default:0)) diff_ports
    end
  done;
  !first, List.sort compare (Hashtbl.fold (fun n c l -> (n, c) :: l) per_diff [])

(* a Yosys counterexample (the log of sat -show-inputs -show-outputs) as a programme trace:
   step 1 clears; step n >= 2 is thread (n - 2) mod 4's slot, executing that step's imem_data *)
let decode file =
  let ic = open_in file in
  let rows = ref [] in
  (try
     while true do
       let l = input_line ic in
       match String.split_on_char ' ' l |> List.filter (( <> ) "") with
       | step :: name :: dec :: _ when String.length name > 1 && name.[0] = '\\' ->
         (match int_of_string_opt step, int_of_string_opt dec with
          | Some st, Some v -> rows := (st, String.sub name 1 (String.length name - 1), v) :: !rows
          | _ -> ())
       | _ -> ()
     done
   with End_of_file -> close_in ic);
  let rows = List.rev !rows in
  let steps = List.sort_uniq compare (List.map (fun (s, _, _) -> s) rows) in
  List.iter (fun st ->
      let get n = List.find_map (fun (s, m, v) -> if s = st && m = n then Some v else None) rows in
      let diffs = List.filter_map (fun (s, m, v) ->
          if s = st && v = 1 && String.length m > 5 && String.sub m 0 5 = "diff_" then Some (String.sub m 5 (String.length m - 5)) else None) rows in
      match get "imem_data" with
      | Some w when st >= 2 ->
        Printf.printf "  step %2d  thread %d  %04x  %-30s%s\n" st ((st - 2) mod 4) w (Isa2.disasm w)
          (if diffs = [] then "" else "  <- differs: " ^ String.concat ", " diffs)
      | _ -> if st = 1 then Printf.printf "  step  1  clear\n") steps

let () =
  if Array.length Sys.argv = 3 && Sys.argv.(1) = "--decode" then (decode Sys.argv.(2); exit 0);
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--list" then (List.iter (fun (_, d) -> print_endline d) Sequencer2.bugs; exit 0)

let () =
  if Array.length Sys.argv >= 2 && Sys.argv.(1) = "--sim" then begin
    let cycles = int_of_string Sys.argv.(2) in
    let bug = if Array.length Sys.argv > 3 then Some (fst (List.find (fun (_, d) -> d = Sys.argv.(3)) Sequencer2.bugs)) else None in
    let first, diffs = simulate ?bug ~cycles ~seed:1 () in
    Printf.printf "simulated %d random clocks%s: %s%s\n" cycles
      (match bug with Some _ -> " with bug \"" ^ Sys.argv.(3) ^ "\"" | None -> "")
      (match first with Some c -> Printf.sprintf "first mismatch at clock %d" c | None -> "no mismatch")
      (String.concat "" (List.map (fun (n, c) -> Printf.sprintf " %s:%d" n c) diffs));
    exit 0
  end

let () =
  let file = Sys.argv.(1) in
  let bug =
    match Array.to_list Sys.argv with
    | [ _; _ ] -> None
    | [ _; _; name ] ->
      (match List.find_opt (fun (_, d) -> d = name) Sequencer2.bugs with
       | Some (b, _) -> Some b
       | None ->
         prerr_endline "bugs (pass the description as the argument):";
         List.iter (fun (_, d) -> prerr_endline ("  " ^ d)) Sequencer2.bugs;
         exit 2)
    | _ -> prerr_endline "usage: miter.exe FILE [BUG-DESCRIPTION]"; exit 2 in
  let oc = open_out file in
  Rtl.output ~output_mode:(To_channel oc) Verilog (circuit ?bug ());
  close_out oc
