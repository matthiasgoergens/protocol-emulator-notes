(* Longest register-to-register paths of the chip on the Hardcaml graph, before synthesis, with the
   OCaml call sites of every signal on them.  A locator for the paths STA reports, whose
   intermediate nets lose their names in synthesis; the delay model is a gate-level count, not time.
   [rtlpaths.exe [SIZES] [N]]: the N worst endpoints (default 20) of the chip with segment SIZES.

   Delay model, in gate levels: and/or/xor 1; ==: 1 + log2 width; +:, -:, <: one level per bit (a
   ripple, as area-mode synthesis builds them); a mux 1 + log2 cases after its select, log2 cases
   after its data; wires, selects, concatenations and inversions 0. Registers, memory read ports and
   instance outputs start at 0; endpoints are register d/enable/clear and memory and instance inputs. *)
open Hardcaml

let ours (f : string) =
  let skip = [ "hardcaml"; "stdlib"; "base/"; "camlinternal"; "list.ml"; "array.ml"; "comb.ml"; "signal.ml";
               "always.ml"; "interface.ml"; "scope.ml"; "caller_id.ml"; "signal__type.ml"; "bits.ml";
               "with_valid.ml"; "bin/rtlpaths.ml"; "src/tt_top.ml" ] in
  not (List.exists (fun s -> let n = String.length s in
                     let rec go i = i + n <= String.length f && (String.sub f i n = s || go (i + 1)) in go 0) skip)

let frames s =
  match Signal.Type.caller_id s with
  | None -> []
  | Some id ->
    let rec atoms (x : Sexplib0.Sexp.t) = match x with Atom a -> [ a ] | List l -> List.concat_map atoms l in
    atoms (Caller_id.sexp_of_t id) |> List.filter ours
    |> List.fold_left (fun acc f -> if List.mem f acc then acc else f :: acc) [] |> List.rev

let strip f = match String.rindex_opt f ':' with Some i -> String.sub f 0 i | None -> f

let where s = String.concat " < " (List.map strip (List.filteri (fun i _ -> i < 3) (frames s)))

let name s =
  match Signal.names s with n :: _ -> n | [] -> "_" ^ Signal.Type.Uid.to_string (Signal.uid s)

let log2 n = let rec go k = if 1 lsl k >= n then k else go (k + 1) in go 0

let () =
  Caller_id.set_mode Full_trace;
  let arg i d = if Array.length Sys.argv > i then Sys.argv.(i) else d in
  let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' (arg 1 "1,1,1,1"))) in
  let n = int_of_string (arg 2 "20") in
  (* optional: only paths from the register named START (an anonymous one is _UID), to END *)
  let start = arg 3 "" and stop = arg 4 "" in
  let cfg = { Chip_spec.layout = Upe.Spec.layout_of_sizes sizes; prog_words = 512 } in
  Chip_rtl.bug := "";
  let c = Tt_top.create ~cfg ~memories:`Macros ~name:"chip_tt" () in
  let module T = Signal.Type in
  let key s = T.Uid.to_string (Signal.uid s) in
  let arr : (string, float * Signal.t option) Hashtbl.t = Hashtbl.create 100000 in
  let rec at s : float =
    if Signal.is_empty s then 0. else
    match Hashtbl.find_opt arr (key s) with
    | Some (a, _) -> a
    | None ->
      let best l = List.fold_left (fun (a, p) (x, extra) -> let t = at x +. extra in if t > a then (t, Some x) else (a, p)) (neg_infinity, None) l in
      let a, p =
        match s with
        | T.Reg _ | T.Mem_read_port _ | T.Inst _ | T.Multiport_mem _ | T.Const _ | T.Empty ->
          ((if start = "" || name s = start then 0. else neg_infinity), None)
        | T.Wire { driver; _ } -> if Signal.is_empty !driver then (0., None) else best [ (!driver, 0.) ]
        | T.Not { arg; _ } | T.Select { arg; _ } -> best [ (arg, 0.) ]
        | T.Cat { args; _ } -> best (List.map (fun x -> (x, 0.)) args)
        | T.Op2 { op; arg_a; arg_b; _ } ->
          let w = float (Signal.width arg_a) in
          let d = match op with
            | Signal_and | Signal_or | Signal_xor -> 1.
            | Signal_eq -> 1. +. float (log2 (Signal.width arg_a))
            | Signal_add | Signal_sub | Signal_lt -> w
            | Signal_mulu | Signal_muls -> 2. *. w in
          best [ (arg_a, d); (arg_b, d) ]
        | T.Mux { select; cases; _ } ->
          let l = float (log2 (List.length cases)) in
          best ((select, 1. +. l) :: List.map (fun x -> (x, l)) cases)
      in
      Hashtbl.replace arr (key s) (a, p); a
  in
  (* endpoints *)
  let ends = ref [] in
  Signal_graph.iter (Circuit.signal_graph c) ~f:(fun s ->
      match s with
      | T.Reg { d; register; _ } ->
        let cands = [ (d, 0.); (register.reg_enable, 1.); (register.reg_clear, 1.) ]
                    |> List.filter (fun (x, _) -> not (Signal.is_empty x)) in
        let a, via = List.fold_left (fun (a, v) (x, e) -> let t = at x +. e in if t > a then (t, Some x) else (a, v)) (neg_infinity, None) cands in
        ends := (a, s, via) :: !ends
      | T.Inst { instantiation; _ } ->
        List.iter (fun (_, x) -> ends := (at x, s, Some x) :: !ends) instantiation.inst_inputs
      | _ -> ());
  let ends = List.filter (fun (a, s, _) -> a > neg_infinity && (stop = "" || name s = stop)) !ends in
  let ends = List.sort (fun (a, _, _) (b, _, _) -> compare b a) ends in
  (* one line per endpoint origin (a 16-bit register is one endpoint) *)
  let seen = Hashtbl.create 100 in
  let k = ref 0 in
  List.iter (fun (a, s, via) ->
      let w = where s in
      if !k < n && not (Hashtbl.mem seen w) then begin
        Hashtbl.add seen w (); incr k;
        Printf.printf "\n%2d. depth %.0f  end %s (%s, %d bits) @ %s\n" !k a (name s)
          (match s with T.Reg _ -> "reg" | T.Inst _ -> "macro input" | _ -> "?") (Signal.width s) w;
        let rec chain x acc = match x with
          | None -> acc
          | Some x -> chain (snd (Hashtbl.find arr (key x))) (x :: acc) in
        let ch = chain via [] in
        let last = ref "" in
        List.iter (fun x ->
            let wx = where x in
            if wx <> !last && wx <> "" then begin
              last := wx;
              Printf.printf "      %5.0f  %-8s %s\n" (at x) (name x) wx end) ch
      end) ends
