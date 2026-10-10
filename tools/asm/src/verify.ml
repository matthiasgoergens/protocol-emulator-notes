(* asm --verify: each .timing block is proved for its thread by the repository's static timing
   verifier (../../prototypes/verifier: the untrusted analyser finds an invariant table, the
   trusted kernel checks it), and the timing certificate is written. The certificate's format is
   the verifier's own (main.ml, cert_text), so its ledger tools read it.

   What the verifier assumes (its kernel.ml, A1-A5) applies here unchanged; in particular A3: the
   thread runs from pc 0 of its page. A .timing block for a thread that starts elsewhere is
   refused rather than proved about the wrong entry point. A5 (no other thread writes the
   channel's pins) is checked here as the verifier's [compose] does: every other thread that
   starts at pc 0 is analysed without a specification, and the pins its reachable code writes must
   not meet the channel. A thread that starts elsewhere cannot be analysed, and that is reported. *)

module V = Verif
open V

type verdict = { name : string; thread : int; ok : bool; text : string; cert : string option }

let disasm = Isa2.disasm

let cert_text ~name (spec : Spec.t) words (rep : Kernel.report) ~accepted =
  let b = Buffer.create 4096 in
  let p fmt = Printf.bprintf b fmt in
  let sha = Sha256.digest (Sha256.image_bytes words) in
  p "# timing certificate\n# image %s sha256 %s (256 words, high byte first)\n" name sha;
  p "# specification: %s, channel pins %s\n" spec.name (String.concat "," (List.map string_of_int spec.pins));
  p "# verdict: %s; %d table entries, %d channel events checked\n" (if accepted then "PROVED" else "REJECTED")
    rep.entries rep.events_checked;
  p "# assumptions: kernel.ml A1-A5. Slot s of thread t is clock 4s+t; q is the quarter-clock sub-slot\n";
  p "# columns: pc, instruction, pins touched, specification state from -> to, slot of the event,\n";
  p "#          gap since the previous channel event, declared gap, declared data (the level is that\n";
  p "#          bit of that input byte: driven for a push-pull write, driven 0 or released for open drain)\n";
  (match spec.bytes with
   | [||] -> ()
   | bs -> p "# input bytes: %s\n" (String.concat " " (Array.to_list (Array.mapi (fun i x -> Printf.sprintf "byte%d=0x%02x" i x) bs))));
  p "# deadlines: %s\n" (String.concat " " (List.filter_map (fun a -> match Spec.deadline spec a with
      | Some d -> Some (Printf.sprintf "%d:%d" a d) | None -> None) (List.init spec.states Fun.id)));
  let preds = List.sort_uniq compare (List.map (fun (x : Kernel.prediction) ->
      (x.p_time.Interval.lo, x.p_pc, x.p_from, Interval.to_string x.p_time,
       Spec.event_to_string x.p_ev, x.p_to, Option.map Interval.to_string x.p_gap,
       Option.map Interval.to_string x.p_allowed, x.p_q, x.p_word, x.p_data)) rep.predictions) in
  List.iter (fun (_, pc, from, time, ev, to_, gap, allowed, q, w, data) ->
      p "%3d  %-26s %-26s %3d -> %-3s slot %-10s%s gap %-9s declared %s%s\n" pc (disasm w) ev from
        (match to_ with Some t -> string_of_int t | None -> "-") time (if q <> 0 then Printf.sprintf " q%d" q else "")
        (Option.value gap ~default:"-") (Option.value allowed ~default:"-")
        (match data with Some d -> " data " ^ Spec.data_to_string d | None -> "")) preds;
  List.iter (fun x -> p "VIOLATION %s\n" (Kernel.violation_to_string spec x)) rep.violations;
  Buffer.contents b

let path_text spec (res : Analyser.result) words k =
  let p = Analyser.path res k in
  let len = List.length p and n = 14 in
  let b = Buffer.create 512 in
  Printf.bprintf b "    path (%d instructions from pc 0%s):\n" len (if len > n then Printf.sprintf ", last %d shown" n else "");
  List.iteri (fun i (k : Kernel.key) ->
      if i >= len - n then
        let value = match Analyser.value_of res k with Some x -> Kernel.value_to_string x | None -> "" in
        Printf.bprintf b "      %3d  %-28s state %-34s %s\n" k.pc (disasm words.(k.pc))
          (let s = spec.Spec.state_name k.astate in if String.length s > 34 then String.sub s 0 34 else s) value) p;
  Buffer.contents b

(* the pins a thread's reachable code writes, if it starts at pc 0 of its page *)
let written (img : Image.t) (page, pc) =
  if pc <> 0 then None
  else
    let words = Image.page_words img page in
    let spec = Spec.unconstrained "ownership" in
    let res = Analyser.analyse spec words in
    Some (Kernel.check spec words res.cert).written

let verify ~name (r : Assembler.result) =
  List.map (fun ((t : Assembler.timing), spec) ->
      let th = t.thread in
      let page, pc = r.threads.(th) in
      let vname = Printf.sprintf "%s.t%d" name th in
      if pc <> 0 then
        { name = vname; thread = th; ok = false; cert = None;
          text = Printf.sprintf "thread %d: NOT VERIFIED: it starts at page %d pc %d, and the verifier analyses a thread from pc 0 of its page (its assumption A3); move the thread's entry to pc 0\n" th page pc }
      else begin
        let words = Image.page_words r.image page in
        let res = Analyser.analyse spec words in
        let rep = Kernel.check spec words res.cert in
        let vacuous = rep.violations = [] && rep.events_checked = 0 in
        let accepted = rep.violations = [] && not vacuous in
        let owned = List.fold_left (fun m (tr : Spec.transition) ->
            List.fold_left (fun m (p, pat) -> match pat with
                | Spec.Set _ | Spec.Data_pp | Spec.Data_od -> m lor (1 lsl p) | _ -> m) m tr.pats) 0 spec.transitions in
        let others = List.filter_map (fun th' ->
            if th' = th then None
            else Some (th', written r.image r.threads.(th'))) [ 0; 1; 2; 3 ] in
        let clashes = List.filter_map (fun (th', w) -> match w with
            | Some w when w land owned <> 0 -> Some (Printf.sprintf "thread %d's code writes pins 0x%02x of this channel" th' (w land owned))
            | _ -> None) others in
        let unchecked = List.filter_map (fun (th', w) -> if w = None then Some th' else None) others in
        let b = Buffer.create 1024 in
        (* A5 must be checked for every other thread: one the analyser cannot start (pc <> 0)
           could write the channel, so its presence refuses the proof *)
        let ok = accepted && clashes = [] && unchecked = [] in
        Printf.bprintf b "thread %d (page %d): %s  table entries %d, channel events checked %d\n" th page
          (if ok then "PROVED" else "REJECTED") rep.entries rep.events_checked;
        if vacuous then Printf.bprintf b "    no channel event was checked: the specification is vacuous here\n";
        List.iteri (fun i x ->
            if i < 3 then begin
              Printf.bprintf b "    %s\n" (Kernel.violation_to_string spec x);
              if i = 0 then match Kernel.violation_key x with Some k -> Buffer.add_string b (path_text spec res words k) | None -> ()
            end) rep.violations;
        if List.length rep.violations > 3 then Printf.bprintf b "    ... %d violations in all\n" (List.length rep.violations);
        List.iter (fun s -> Printf.bprintf b "    OWNERSHIP: %s\n" s) clashes;
        if unchecked <> [] then
          Printf.bprintf b "    NOT PROVED: thread%s %s start%s at a pc other than 0, so the verifier cannot check that %s code leaves the channel's pins alone (assumption A5)\n"
            (if List.length unchecked > 1 then "s" else "") (String.concat ", " (List.map string_of_int unchecked))
            (if List.length unchecked > 1 then "" else "s") (if List.length unchecked > 1 then "their" else "its");
        { name = vname; thread = th; ok; text = Buffer.contents b;
          cert = Some (cert_text ~name:vname spec words rep ~accepted) }
      end) r.timings
