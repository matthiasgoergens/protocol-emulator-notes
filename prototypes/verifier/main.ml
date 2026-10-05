(* Command line of the verifier. README.md says what each command shows.

     main.exe selftest          the verifier's own teeth: SHA-256 vectors, every planted bug
                                rejected, a correct programme accepted
     main.exe verify NAME       one image of the sweep or the planted list, with its table
     main.exe sweep             every image of the compiler sweep: verdict and interpreter
                                cross-check
     main.exe planted           the planted bugs: each must be rejected, with its path
     main.exe precision         correct hand-written programmes that are hard for the analysis
     main.exe compose           ownership across threads for the demo composition
     main.exe mutants           single-word mutants: verdict against the interpreter
     main.exe random N          random programmes: certificate against the interpreter
     main.exe controls          perturbed certificates: the kernel must reject each
     main.exe certs DIR         per-image timing certificates and the ledger
     main.exe ledger-check FILE recompute every certificate and compare with the ledger
     main.exe kernel-bugs       planted bugs in the kernel: each must make a check above fail *)

open Programmes

type verdict = {
  img : image;
  res : Analyser.result;
  rep : Kernel.report;
  vacuous : string option;     (* a specification with a channel whose events were never checked *)
}

let accepted v = v.rep.violations = [] && v.vacuous = None

let verify img =
  let res = Analyser.analyse img.spec img.words in
  let rep = Kernel.check img.spec img.words res.cert in
  let vacuous =
    if img.spec.pins <> [] && rep.violations = [] && rep.events_checked = 0 then Some "no channel event was checked: the specification is vacuous here"
    else None in
  { img; res; rep; vacuous }

let disasm w = Isa2.disasm w

(* the path from pc 0 to the key of the first violation, last [n] steps *)
let print_path ?(n = 14) v k =
  let p = Analyser.path v.res k in
  let len = List.length p in
  Printf.printf "    path (%d instructions from pc 0%s):\n" len (if len > n then Printf.sprintf ", last %d shown" n else "");
  List.iteri (fun i (k : Kernel.key) ->
      if i >= len - n then
        let value = match Analyser.value_of v.res k with Some x -> Kernel.value_to_string x | None -> "" in
        Printf.printf "      %3d  %-28s state %-34s %s\n" k.pc (disasm v.img.words.(k.pc))
          (let s = v.img.spec.state_name k.astate in if String.length s > 34 then String.sub s 0 34 else s) value) p

let summary v =
  Printf.sprintf "%-44s %s  entries %5d  events %5d%s" v.img.name
    (if accepted v then "PROVED  " else "REJECTED") v.rep.entries v.rep.events_checked
    (match v.vacuous with Some s -> "  (" ^ s ^ ")" | None -> "")

let print_rejection v =
  print_endline (summary v);
  (match v.vacuous with Some s -> Printf.printf "    %s\n" s | None -> ());
  let shown = ref 0 in
  List.iter (fun x ->
      if !shown < 3 then begin
        incr shown;
        Printf.printf "    %s\n" (Kernel.violation_to_string v.img.spec x);
        match Kernel.violation_key x with Some k when !shown = 1 -> print_path v k | _ -> ()
      end) v.rep.violations;
  if List.length v.rep.violations > 3 then Printf.printf "    ... %d violations in all\n" (List.length v.rep.violations)

(* ---- certificates ---- *)

let cert_text v =
  let b = Buffer.create 4096 in
  let p fmt = Printf.bprintf b fmt in
  let sha = Sha256.digest (Sha256.image_bytes v.img.words) in
  p "# timing certificate\n# image %s sha256 %s (256 words, high byte first)\n" v.img.name sha;
  p "# specification: %s, channel pins %s\n" v.img.spec.name (String.concat "," (List.map string_of_int v.img.spec.pins));
  p "# verdict: %s; %d table entries, %d channel events checked\n" (if accepted v then "PROVED" else "REJECTED")
    v.rep.entries v.rep.events_checked;
  p "# assumptions: kernel.ml A1-A4. Slot s of thread t is clock 4s+t; q is the quarter-clock sub-slot\n";
  p "# columns: pc, instruction, pins touched, specification state from -> to, slot of the event,\n";
  p "#          gap since the previous channel event, declared gap\n";
  let preds = List.sort_uniq compare (List.map (fun (x : Kernel.prediction) ->
      (x.p_time.Interval.lo, x.p_pc, x.p_from, Interval.to_string x.p_time,
       Spec.event_to_string x.p_ev, x.p_to, Option.map Interval.to_string x.p_gap,
       Option.map Interval.to_string x.p_allowed, x.p_q, x.p_word)) v.rep.predictions) in
  List.iter (fun (_, pc, from, time, ev, to_, gap, allowed, q, w) ->
      p "%3d  %-26s %-26s %3d -> %-3s slot %-10s%s gap %-9s declared %s\n" pc (disasm w) ev from
        (match to_ with Some t -> string_of_int t | None -> "-") time (if q <> 0 then Printf.sprintf " q%d" q else "")
        (Option.value gap ~default:"-") (Option.value allowed ~default:"-")) preds;
  List.iter (fun x -> p "VIOLATION %s\n" (Kernel.violation_to_string v.img.spec x)) v.rep.violations;
  Buffer.contents b

let ledger_line v =
  let text = cert_text v in
  Printf.sprintf "%s %s %s %s" (Sha256.digest (Sha256.image_bytes v.img.words)) (Sha256.digest text)
    (if accepted v then "PROVED" else "REJECTED") v.img.name

(* ---- commands ---- *)

let all_images () = sweep () @ planted ()

let find name = match List.find_opt (fun i -> i.name = name) (all_images ()) with
  | Some i -> i | None -> prerr_endline ("no image " ^ name); exit 2

let cmd_verify name =
  let v = verify (find name) in
  if accepted v then print_endline (summary v) else print_rejection v;
  print_string (cert_text v)

(* Seeds for the interpreter runs. An I2C image with a short stretch limit also gets the targeted
   runs (Sim): each release in turn stretched by every whole number of slots up to the limit
   and past it. *)
let seeds_for img = match img.env with
  | Pull_up -> [ 1 ]
  | I2c_slave _ ->
    let lm = List.fold_left (fun m (tr : Spec.transition) ->
        match tr.pats with [ (_, Spec.Timeout _) ] -> max m tr.gap.Interval.lo | _ -> m) 0 img.spec.transitions in
    let releases = List.length (List.filter (fun (tr : Spec.transition) ->
        match tr.pats with [ (_, Spec.Timeout _) ] -> true | _ -> false) img.spec.transitions) in
    List.init 12 (fun i -> i + 1)
    @ (if lm > 16 then [] else
         List.concat_map (fun n -> List.map (fun m -> 1000 + (64 * n) + m) (List.init (lm + 2) Fun.id @ [ 63 ]))
           (List.init releases (fun i -> i + 1)))
  | Random_inputs -> List.init 12 (fun i -> i + 1)

(* run [img] on the interpreter with each seed: (all states covered, every run meets the spec,
   first message) *)
let cross_check v =
  let runs = List.map (fun seed -> Sim.run ~seed v.res.cert v.img) (seeds_for v.img) in
  let uncovered = List.concat_map (fun (r : Sim.measured) -> r.uncovered) runs in
  let bad = List.filter_map (fun (r : Sim.measured) -> match r.meets_spec with Error s -> Some s | Ok () -> None) runs in
  let entries = List.fold_left (fun a (r : Sim.measured) -> a + r.entries) 0 runs in
  let events = List.fold_left (fun a (r : Sim.measured) -> a + r.events) 0 runs in
  uncovered, bad, entries, events, List.length runs

let cmd_sweep () =
  let imgs = sweep () in
  let n = List.length imgs in
  let acc = ref 0 and rej = ref 0 and false_rej = ref 0 and unsound = ref 0 and uncov = ref 0 in
  let entries = ref 0 and events = ref 0 and runs = ref 0 in
  List.iter (fun img ->
      let v = verify img in
      let u, bad, e, ev, nr = cross_check v in
      entries := !entries + e; events := !events + ev; runs := !runs + nr;
      if u <> [] then (incr uncov; Printf.printf "  CROSS-CHECK FAILED %s: %s\n" img.name (List.hd u));
      if accepted v then begin
        incr acc;
        if bad <> [] then (incr unsound; Printf.printf "  UNSOUND %s: proved, but a run fails: %s\n" img.name (List.hd bad))
      end else begin
        incr rej;
        if bad = [] then incr false_rej;
        print_rejection v;
        (match bad with s :: _ -> Printf.printf "    interpreter run also fails: %s\n" s
                      | [] -> Printf.printf "    every interpreter run meets the specification\n")
      end;
      Printf.printf "%s  cross-check %d runs %s\n%!" (summary v) nr (if u = [] then "covered" else "NOT COVERED")) imgs;
  Printf.printf "\nsweep: %d images; proved %d, rejected %d (of which %d with every interpreter run meeting the specification)\n"
    n !acc !rej !false_rej;
  Printf.printf "interpreter cross-check: %d runs, %d instruction entries and %d channel events measured; images with a measured state outside the certificate: %d; proved images with a failing run: %d\n"
    !runs !entries !events !uncov !unsound;
  if !uncov > 0 || !unsound > 0 then exit 1

let cmd_precision () =
  List.iter (fun img ->
      let v = verify img in
      let _, bad, _, _, nr = cross_check v in
      if accepted v then print_endline (summary v) else print_rejection v;
      Printf.printf "    interpreter (%d runs): %s\n" nr
        (match bad with s :: _ -> "fails: " ^ s | [] -> "every run meets the specification")) (precision_cases ())

let cmd_planted () =
  let missed = ref 0 in
  List.iter (fun img ->
      let v = verify img in
      let _, bad, _, _, nr = cross_check v in
      if accepted v then (incr missed; Printf.printf "%s\n    NOT REJECTED: the verifier accepts a planted bug\n" (summary v))
      else print_rejection v;
      Printf.printf "    interpreter (%d run%s): %s\n\n" nr (if nr = 1 then "" else "s")
        (match bad with s :: _ -> "fails: " ^ s | [] -> "no run fails the specification (the bug needs inputs the runs did not make)")) (planted ());
  Printf.printf "planted: %d bugs, %d not rejected\n" (List.length (planted ())) !missed;
  if !missed > 0 then exit 1

(* The demo composition (../deadline-sequencer/demo.ml): UART on thread 0, SPI on 1, I2C on 2,
   the watchdog on 3. Each thread's specification is proved alone (threads cannot delay each
   other), and a thread's channel pins that its specification writes must not be written by
   any other thread's reachable code. *)
let compose ?(watchdog_mask = 0x80) () =
  let imgs = [ uart ~thread:0 ~b:16 [ 0x4F; 0x4B; 0x21 ]; spi ~thread:1 ~p:16 [ 0xA5; 0x3C ];
               i2c ~thread:2 ~q:4 [ 0xA0; 0x5A ];
               { (watchdog ()) with words = watchdog_words ~timeout_mask:watchdog_mask;
                                    name = Printf.sprintf "watchdog mask=0x%02x" watchdog_mask } ] in
  let vs = List.map verify imgs in
  let owned (v : verdict) = List.fold_left (fun m (tr : Spec.transition) ->
      List.fold_left (fun m (p, pat) -> match pat with Spec.Set _ | Spec.Data_pp | Spec.Data_od -> m lor (1 lsl p) | _ -> m) m tr.pats)
      0 v.img.spec.transitions in
  let clashes = List.concat_map (fun a -> List.filter_map (fun b ->
      if a.img.thread <> b.img.thread && owned a land b.rep.written <> 0 then
        Some (Printf.sprintf "thread %d (%s) writes pins 0x%02x of thread %d's channel (%s)" b.img.thread b.img.name
                (owned a land b.rep.written) a.img.thread a.img.name)
      else None) vs) vs in
  List.iter (fun v -> Printf.printf "  thread %d: %s; writes pins 0x%02x\n" v.img.thread (summary v) v.rep.written) vs;
  List.iter (fun s -> Printf.printf "  OWNERSHIP: %s\n" s) clashes;
  List.for_all accepted vs && clashes = []

let cmd_compose () =
  print_endline "demo composition:";
  let ok = compose () in
  Printf.printf "composition: %s\n\nplanted: the watchdog's timeout writes pin 0 (mask 0x01, the UART's pin):\n" (if ok then "PROVED" else "REJECTED");
  let bad = compose ~watchdog_mask:0x01 () in
  Printf.printf "composition: %s\n" (if bad then "PROVED (planted bug missed)" else "REJECTED");
  if not ok || bad then exit 1

(* ---- mutants ---- *)

(* every reachable instruction has one outcome, taking a known number of slots: then one run of
   the interpreter is the whole truth *)
let deterministic v =
  List.for_all (fun ((k : Kernel.key), (x : Kernel.value)) ->
      match Kernel.transfer v.img.words.(k.pc) k x.dl with
      | [ r ] -> Interval.is_exact r.elapsed && Interval.is_exact r.at
      | _ -> false) v.res.cert

let mutants_of img =
  let w = img.words in
  let len = let rec last i = if i < 0 then 0 else if w.(i) <> 0 then i + 1 else last (i - 1) in last 255 in
  let rng = Random.State.make [| 7 |] in
  let ms = ref [] in
  let add desc f = let c = Array.copy w in f c; ms := (desc, c) :: !ms in
  for i = 0 to len - 1 do
    let x = w.(i) and op = (w.(i) lsr 12) land 15 in
    add (Printf.sprintf "pc %d -> nop" i) (fun c -> c.(i) <- 0);
    if op = 2 || op = 3 then begin
      add (Printf.sprintf "pc %d imm+1" i) (fun c -> c.(i) <- (x land 0xF000) lor ((x + 1) land 0xFFF));
      add (Printf.sprintf "pc %d imm-1" i) (fun c -> c.(i) <- (x land 0xF000) lor ((x - 1) land 0xFFF))
    end;
    if op = 5 || op = 9 || op = 10 || op = 13 || op = 14 then begin
      add (Printf.sprintf "pc %d target+1" i) (fun c -> c.(i) <- (x land 0xFF00) lor ((x + 1) land 0xFF));
      add (Printf.sprintf "pc %d target-1" i) (fun c -> c.(i) <- (x land 0xFF00) lor ((x - 1) land 0xFF))
    end;
    if i + 1 < len then add (Printf.sprintf "pc %d swap with next" i) (fun c -> c.(i) <- w.(i + 1); c.(i + 1) <- x);
    let r = Random.State.int rng 0x10000 in
    add (Printf.sprintf "pc %d random word %04x (%s)" i r (disasm r)) (fun c -> c.(i) <- r)
  done;
  List.rev !ms

let cmd_mutants () =
  let bases = [ uart ~b:8 [ 0xA5 ]; spi ~p:12 [ 0xA5 ]; i2c ~q:4 ~lm:7 [ 0xA0 ]; deadline (); watchdog () ] in
  let tot = ref 0 and tp = ref 0 and tn = ref 0 and fr = ref 0 and unsound = ref 0 and uncov = ref 0 in
  let fr_det = ref 0 and ok_det = ref 0 in
  List.iter (fun base ->
      let b_tp = ref 0 and b_tn = ref 0 and b_fr = ref 0 and b_n = ref 0 in
      List.iter (fun (desc, words) ->
          let img = { base with words; name = base.name ^ " " ^ desc } in
          let v = verify img in
          let u, bad, _, _, _ = cross_check v in
          incr tot; incr b_n;
          if u <> [] then (incr uncov; Printf.printf "  CROSS-CHECK FAILED %s: %s\n" img.name (List.hd u));
          let det = deterministic v in
          match accepted v, bad with
          | true, [] -> incr tn; incr b_tn; if det then incr ok_det
          | true, s :: _ -> incr unsound; Printf.printf "  UNSOUND %s: proved, but a run fails: %s\n" img.name s
          | false, _ :: _ -> incr tp; incr b_tp
          | false, [] ->
            incr fr; incr b_fr; if det then incr fr_det;
            Printf.printf "  rejected, no run fails (%s): %s\n    %s\n" (if det then "deterministic: a false rejection" else "input-dependent")
              img.name (match v.rep.violations with x :: _ -> Kernel.violation_to_string img.spec x | [] -> Option.value v.vacuous ~default:"")) (mutants_of base);
      Printf.printf "%-28s %4d mutants: rejected and a run fails %4d; proved and every run meets %4d; rejected, no run fails %3d\n%!"
        base.name !b_n !b_tp !b_tn !b_fr) bases;
  Printf.printf "\nmutants: %d; rejected with a failing run %d; proved %d; proved but a run fails (UNSOUND) %d; rejected with no failing run %d (deterministic programmes: %d of %d that meet the specification)\n"
    !tot !tp !tn !unsound !fr !fr_det (!fr_det + !ok_det);
  Printf.printf "measured states outside the certificate: %d mutants\n" !uncov;
  if !unsound > 0 || !uncov > 0 then exit 1

(* ---- random programmes ---- *)

let random_words rng =
  let len = 4 + Random.State.int rng 40 in
  Array.init Isa2.page_len (fun i ->
      if i >= len then 0
      else
        let op = Random.State.int rng 16 in
        let f = Random.State.int rng 0x1000 in
        (* keep addresses inside the programme most of the time, and immediates small enough that
           loops end within the run *)
        let f = match op with
          | 2 | 3 -> Random.State.int rng (if Random.State.int rng 8 = 0 then 4096 else 12)
          | 5 | 9 | 10 | 13 | 14 -> (f land 0xF00) lor Random.State.int rng (len + 2)
          | _ -> f in
        (op lsl 12) lor (f land 0xFFF))

let cmd_random n =
  let rng = Random.State.make [| 2026 |] in
  let spec = Spec.unconstrained "random" in
  let bad = ref 0 and entries = ref 0 and runs = ref 0 in
  for i = 1 to n do
    let words = random_words rng in
    let img = { name = Printf.sprintf "random%d" i; words; spec; thread = i mod 4; env = Random_inputs } in
    let v = verify img in
    if v.rep.violations <> [] then (incr bad; Printf.printf "random%d: kernel rejects the analyser's table: %s\n" i
                                      (Kernel.violation_to_string spec (List.hd v.rep.violations)));
    List.iter (fun seed ->
        let r = Sim.run ~slots:3000 ~seed v.res.cert img in
        incr runs; entries := !entries + r.entries;
        if r.uncovered <> [] then begin
          incr bad; Printf.printf "random%d seed %d: %s\n" i seed (List.hd r.uncovered);
          Array.iteri (fun pc w -> if w <> 0 then Printf.printf "    %3d %04x %s\n" pc w (disasm w)) words
        end) [ 1; 2; 3 ]
  done;
  Printf.printf "random: %d programmes, %d interpreter runs, %d instruction entries measured; failures %d\n" n !runs !entries !bad;
  if !bad > 0 then exit 1

(* ---- negative controls for the kernel (TeslaCoilerOW's perturbed predictions) ---- *)

let cmd_controls () =
  let imgs = [ uart ~b:16 [ 0x4F; 0x4B ]; spi ~p:16 [ 0xA5 ]; i2c ~q:4 [ 0xA0 ]; deadline () ] in
  let total = ref 0 and missed = ref 0 in
  List.iter (fun img ->
      let v = verify img in
      assert (accepted v);
      let cert = v.res.cert in
      let n = ref 0 and m = ref 0 in
      let try_ desc c =
        incr n; incr total;
        let rep = Kernel.check img.spec img.words c in
        if rep.violations = [] then (incr m; incr missed; Printf.printf "  NOT REJECTED %s: %s\n" img.name desc) in
      List.iteri (fun i ((k : Kernel.key), (x : Kernel.value)) ->
          let others = List.filteri (fun j _ -> j <> i) cert in
          let with_ y = List.mapi (fun j e -> if j = i then (k, y) else e) cert in
          let sh (iv : Interval.t) d = Interval.shift iv d in
          try_ (Printf.sprintf "entry %d removed" i) others;
          try_ (Printf.sprintf "entry %d since +1" i) (with_ { x with since = sh x.since 1 });
          if x.since.lo > 0 && x.since.hi <> None then try_ (Printf.sprintf "entry %d since -1" i) (with_ { x with since = sh x.since (-1) });
          try_ (Printf.sprintf "entry %d time +1" i) (with_ { x with time = sh x.time 1 });
          if x.dl.hi <> Some 4095 then try_ (Printf.sprintf "entry %d dl +1" i) (with_ { x with dl = sh x.dl 1 });
          if x.due.hi <> None then try_ (Printf.sprintf "entry %d due +1" i) (with_ { x with due = sh x.due 1 })) cert;
      (* the declared gaps, perturbed: the kernel checks the certificate against a specification
         whose every declared gap is moved by one slot in turn *)
      List.iteri (fun ti (tr : Spec.transition) ->
          if Interval.is_exact tr.gap then
            List.iter (fun d ->
                let spec = { img.spec with transitions = List.mapi (fun j t -> if j = ti then { t with Spec.gap = Interval.shift t.Spec.gap d } else t) img.spec.transitions } in
                incr n; incr total;
                if (Kernel.check spec img.words cert).violations = [] then
                  (incr m; incr missed; Printf.printf "  NOT REJECTED %s: declared gap of %s %+d\n" img.name tr.label d)) [ -1; 1 ])
        img.spec.transitions;
      Printf.printf "%-28s %5d perturbed certificates or specifications, %d not rejected\n%!" img.name !n !m) imgs;
  Printf.printf "controls: %d, not rejected %d\n" !total !missed;
  if !missed > 0 then exit 1

let cmd_certs dir =
  (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let lines = List.map (fun img ->
      let v = verify img in
      let oc = open_out (Filename.concat dir (img.name ^ ".cert")) in
      output_string oc (cert_text v); close_out oc;
      ledger_line v) (sweep ()) in
  List.iter print_endline lines

let cmd_ledger_check file =
  let ic = open_in file in
  let recorded = Hashtbl.create 512 in
  (try while true do
       let l = input_line ic in
       if l <> "" && l.[0] <> '#' then
         match String.split_on_char ' ' l with
         | img :: cert :: verdict :: name -> Hashtbl.replace recorded (String.concat " " name) (img, cert, verdict)
         | _ -> ()
     done with End_of_file -> ());
  close_in ic;
  let bad = ref 0 and n = ref 0 in
  List.iter (fun img ->
      incr n;
      let v = verify img in
      let line = ledger_line v in
      match String.split_on_char ' ' line, Hashtbl.find_opt recorded img.name with
      | i :: c :: vd :: _, Some (i', c', vd') when i = i' && c = c' && vd = vd' -> ()
      | _, None -> incr bad; Printf.printf "no certificate in the ledger for %s\n" img.name
      | _, Some _ -> incr bad; Printf.printf "ledger differs for %s: now %s\n" img.name line) (sweep ());
  Printf.printf "ledger-check: %d images, %d without a matching certificate\n" !n !bad;
  if !bad > 0 then exit 1

let cmd_selftest () =
  let ok = ref true in
  let expect name b = if not b then (ok := false; Printf.printf "SELFTEST FAILED: %s\n" name) in
  expect "sha256 empty" (Sha256.digest "" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  expect "sha256 abc" (Sha256.digest "abc" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  expect "sha256 two blocks" (Sha256.digest "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
                              = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  expect "a compiled UART is proved" (accepted (verify (uart ~b:16 [ 0x4F ])));
  List.iter (fun img -> expect ("planted bug rejected: " ^ img.name) (not (accepted (verify img)))) (planted ());
  (* a specification with no channel proves nothing about pins; [verify] must not call a
     specification with a channel proved when no channel event was checked *)
  let silent = { (uart ~b:16 [ 0x4F ]) with words = Array.make Isa2.page_len 0 } in
  expect "a programme that never touches its channel is rejected" (not (accepted (verify silent)));
  print_endline (if !ok then "selftest: PASS" else "selftest: FAIL");
  if not !ok then exit 1

(* Each planted kernel bug (Kernel.planted_bug) must make at least one of the verifier's own
   checks fail; each check runs as a child process with the bug set. *)
let kernel_bug_names = [
  1, "a wait that proceeds takes one slot less at most";
  2, "a wait that times out takes one slot less";
  3, "LDD loads one less";
  4, "JNZ falls through on cnt = 1";
  5, "SKNE/SKEQ decided the wrong way";
  6, "a push-pull SHO assumed driven whatever its enable";
  7, "WAITD takes one slot less";
  8, "no deadline check";
  9, "no closure check (every state counts as covered)";
  10, "no gap check" ]

let cmd_kernel_bugs () =
  let checks = [ [ "selftest" ]; [ "controls" ]; [ "random"; "150" ]; [ "sweep" ]; [ "planted" ] ] in
  let missed = ref 0 in
  List.iter (fun (n, desc) ->
      let failed = List.filter (fun args ->
          let cmd = Filename.quote_command Sys.executable_name ("--bug" :: string_of_int n :: args)
              ~stdout:"/dev/null" ~stderr:"/dev/null" in
          Sys.command cmd <> 0) checks in
      if failed = [] then incr missed;
      Printf.printf "kernel bug %2d (%s): %s
%!" n desc
        (if failed = [] then "NOT CAUGHT" else "caught by " ^ String.concat ", " (List.map (String.concat " ") failed)))
    kernel_bug_names;
  Printf.printf "kernel bugs: %d planted, %d not caught
" (List.length kernel_bug_names) !missed;
  if !missed > 0 then exit 1

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let args = match args with
    | "--bug" :: n :: rest -> Kernel.planted_bug := int_of_string n; rest
    | a -> a in
  match args with
  | [ "kernel-bugs" ] -> cmd_kernel_bugs ()
  | [ "selftest" ] -> cmd_selftest ()
  | [ "verify"; name ] -> cmd_verify name
  | [ "sweep" ] -> cmd_sweep ()
  | [ "planted" ] -> cmd_planted ()
  | [ "precision" ] -> cmd_precision ()
  | [ "compose" ] -> cmd_compose ()
  | [ "mutants" ] -> cmd_mutants ()
  | [ "random"; n ] -> cmd_random (int_of_string n)
  | [ "step"; word; acc ] ->
    (* the kernel's outcomes for one instruction word (hex) with acc known (decimal) or "?" *)
    let w = int_of_string ("0x" ^ word) in
    let k = { (Kernel.start_key (Spec.unconstrained "step")) with acc = (if acc = "?" then Any else Known (int_of_string acc)) } in
    Printf.printf "%s\n" (disasm w);
    List.iter (fun (r : Kernel.raw) ->
        Printf.printf "  next pc %d acc %s cnt %s dl %s elapsed %s event %s\n" r.next_pc (Kernel.known_to_string r.acc')
          (Kernel.known_to_string r.cnt') (Interval.to_string r.dl') (Interval.to_string r.elapsed) (Spec.event_to_string r.ev))
      (Kernel.transfer w k (Interval.exactly 0))
  | [ "random-show"; n ] ->
    (* the n-th random programme of [cmd_random], its listing and its table *)
    let rng = Random.State.make [| 2026 |] in
    let words = ref [||] in
    for _ = 1 to int_of_string n do words := random_words rng done;
    let spec = Spec.unconstrained "random" in
    let img = { name = "random" ^ n; words = !words; spec; thread = int_of_string n mod 4; env = Random_inputs } in
    Array.iteri (fun pc w -> if w <> 0 then Printf.printf "%3d %04x %s\n" pc w (disasm w)) !words;
    let v = verify img in
    List.iter (fun ((k : Kernel.key), x) -> Printf.printf "%s %s\n" (Kernel.key_to_string k) (Kernel.value_to_string x)) v.res.cert
  | [ "controls" ] -> cmd_controls ()
  | [ "certs"; dir ] -> cmd_certs dir
  | [ "ledger-check"; file ] -> cmd_ledger_check file
  | [ "list" ] -> List.iter (fun i -> print_endline i.name) (all_images ())
  | _ -> prerr_endline "usage: main.exe [--bug N] selftest|verify NAME|sweep|planted|compose|mutants|random N|controls|certs DIR|ledger-check FILE|list|kernel-bugs"; exit 2
