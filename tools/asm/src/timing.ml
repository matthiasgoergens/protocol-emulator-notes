(* .timing blocks: a thread's timing specification, written in the source next to its code, built
   into the verifier's automaton (../../prototypes/verifier/spec.ml) with the verifier's own
   builder.

     .timing THREAD
       .channel PIN, ...                     the pins the thread owns
       .bytes B, ...                         the input bytes that data declarations refer to
       .expect pN=EVENT ..., gap=G [, byte=I, bit=B] [, to=STATE] [, "label"]
       .state NAME                           name the current state
       .from NAME                            continue from a named state (a branch)
     .endtiming

   EVENT is 0 or 1 (a SETP driving that level), z (a SETP releasing the pin), data (a push-pull
   SHO), data_od (an open-drain SHO), seen0 / seen1 (a WAITP that saw the level), timeout0 /
   timeout1 (a WAITP for that level that timed out) or sample (a SHI). G is N (exactly N slots
   since the previous channel event), A..B, or A.. (at least A). Each .expect is a transition from
   the current state to a new state, which becomes current, or to the named state [to]. A state
   with no transitions is final. *)

module S = Verif.Spec

let event loc key (toks : Lexer.tok list) =
  let pin =
    if String.length key = 2 && key.[0] = 'p' && key.[1] >= '0' && key.[1] <= '7' then Char.code key.[1] - 48
    else Loc.error loc "expected pN=EVENT with N = 0..7, found %s=" key in
  let pat : S.pat = match toks with
    | [ Lexer.Num 0 ] -> Set L | [ Lexer.Num 1 ] -> Set H | [ Lexer.Ident "z" ] -> Set Z
    | [ Lexer.Ident "data" ] -> Data_pp | [ Lexer.Ident "data_od" ] -> Data_od
    | [ Lexer.Ident "seen0" ] -> Seen 0 | [ Lexer.Ident "seen1" ] -> Seen 1
    | [ Lexer.Ident "timeout0" ] -> Timeout 0 | [ Lexer.Ident "timeout1" ] -> Timeout 1
    | [ Lexer.Ident "sample" ] -> Smp
    | t -> Loc.error loc "unknown event %s (0, 1, z, data, data_od, seen0, seen1, timeout0, timeout1, sample)"
             (Syntax.toks_to_string t) in
  (pin, pat)

let gap ~eval loc (toks : Lexer.tok list) : Verif.Interval.t =
  let rec split acc = function
    | Lexer.Op ".." :: r -> (List.rev acc, Some r)
    | t :: r -> split (t :: acc) r
    | [] -> (List.rev acc, None) in
  let check v = if v < 0 then Loc.error loc "gap %d is negative" v; v in
  match split [] toks with
  | a, None -> Verif.Interval.exactly (check (eval loc a))
  | a, Some [] -> Verif.Interval.at_least (check (eval loc a))
  | a, Some b ->
    let lo = check (eval loc a) and hi = check (eval loc b) in
    if hi < lo then Loc.error loc "gap %d..%d is empty" lo hi;
    Verif.Interval.range lo hi

let build ~eval tloc thread (lines : (Loc.t * string * Syntax.arg list) list) =
  let b = S.builder () in
  let names = Hashtbl.create 8 in
  Hashtbl.replace names "start" 0;
  let pins = ref None and bytes = ref [||] in
  let state_of loc name =
    match Hashtbl.find_opt names name with
    | Some s -> s
    | None -> ignore loc; let s = S.fresh b name in Hashtbl.replace names name s; s in
  List.iter (fun (loc, name, args) ->
      let pos = List.filter_map (function Syntax.Pos t -> Some t | _ -> None) args in
      let kws = List.filter_map (function Syntax.Kw (k, t) -> Some (k, t) | _ -> None) args in
      match name with
      | ".channel" ->
        if !pins <> None then Loc.error loc ".channel given twice";
        if pos = [] then Loc.error loc ".channel PIN, ...";
        pins := Some (List.map (fun t -> let p = eval loc t in if p < 0 || p > 7 then Loc.error loc "pin %d out of range" p; p) pos)
      | ".bytes" -> bytes := Array.of_list (List.map (fun t -> eval loc t land 0xFF) pos)
      | ".state" ->
        (match pos with
         | [ [ Lexer.Ident n ] ] ->
           if Hashtbl.mem names n then Loc.error loc "state %s already exists" n;
           Hashtbl.replace names n b.cur;
           b.names <- (b.cur, n) :: b.names
         | _ -> Loc.error loc ".state NAME")
      | ".from" ->
        (match pos with
         | [ [ Lexer.Ident n ] ] -> (match Hashtbl.find_opt names n with
             | Some s -> b.cur <- s
             | None -> Loc.error loc "no state %s yet (name it with .state, or reach it with to=%s)" n n)
         | _ -> Loc.error loc ".from NAME")
      | ".expect" ->
        if !pins = None then Loc.error loc ".channel must come before .expect";
        let pats = List.filter_map (fun (k, t) ->
            if List.mem k [ "gap"; "byte"; "bit"; "to" ] then None else Some (event loc k t)) kws in
        if pats = [] then Loc.error loc ".expect needs at least one pN=EVENT";
        List.iter (fun (p, _) -> if not (List.mem p (Option.get !pins)) then
                      Loc.error loc "pin %d is not in the .channel" p) pats;
        let g = match List.assoc_opt "gap" kws with Some t -> gap ~eval loc t | None -> Loc.error loc ".expect needs gap=" in
        let data = match List.assoc_opt "byte" kws, List.assoc_opt "bit" kws with
          | Some i, Some bt ->
            let i = eval loc i and bt = eval loc bt in
            if i < 0 || i >= Array.length !bytes then Loc.error loc "byte %d: .bytes declares %d" i (Array.length !bytes);
            if bt < 0 || bt > 7 then Loc.error loc "bit %d out of range" bt;
            Some (i, bt)
          | None, None -> None
          | _ -> Loc.error loc "byte= and bit= go together" in
        let label = match pos with
          | [ [ Lexer.Str s ] ] -> s
          | [] -> String.concat " " (List.map (fun (p, pat) -> Printf.sprintf "p%d:%s" p (match pat with
              | S.Set l -> "set=" ^ S.level_to_string l | Data_pp -> "data" | Data_od -> "data_od"
              | Seen v -> Printf.sprintf "seen%d" v | Timeout v -> Printf.sprintf "timeout%d" v | Smp -> "sample")) pats)
          | _ -> Loc.error loc "only a \"label\" may follow the keywords of .expect" in
        (match List.assoc_opt "to" kws with
         | Some [ Lexer.Ident n ] ->
           let dst = state_of loc n in
           S.add ?data b ~src:b.cur pats g ~dst label; b.cur <- dst
         | Some _ -> Loc.error loc "to=STATE"
         | None -> S.step ?data b pats g label)
      | n -> Loc.error loc "%s is not a .timing directive" n) lines;
  let pins = match !pins with Some p -> p | None -> Loc.error tloc ".timing without .channel" in
  try S.finish ~bytes:!bytes b ~name:(Printf.sprintf "thread %d (%s)" thread (Loc.to_string tloc)) ~pins
  with Failure m -> Loc.error tloc "%s" m
