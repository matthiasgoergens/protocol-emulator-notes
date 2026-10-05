(* Helpers for running Latency_lint as a regression test.

   A design is linted in one chosen configuration, and its findings are printed in a form
   that does not depend on signal uids, so that the output can be compared with a committed
   expected file (a dune [diff] rule; [dune promote] accepts a reviewed change). Each design
   also has a planted control, a copy of the design with one register removed from a sync or
   blank path, which must produce a finding the real design does not have. *)
open Base
open Hardcaml
open Hardcaml_latency

(* Locations in findings name the design's own lines, which needs the full OCaml call stack
   in Hardcaml v0.17 (see the vendored library's README). *)
let () = Caller_id.set_mode Full_trace

(* The design's own source line for a signal: the first frame of its creation stack outside
   Hardcaml ("src/..."), the standard library and these two libraries. The vendored lint does
   the same, but only accepts frames with a '/' in them, so it gives no location at all for a
   design whose files sit at the root of its dune project (retro-console, platformer,
   multi-proto, unified-pe); this one keeps them. *)
let stdlib_files =
  Set.of_list
    (module String)
    [ "list.ml"; "array.ml"; "hashtbl.ml"; "fun.ml"; "option.ml"; "seq.ml"; "stdlib.ml"
    ; "map.ml"; "set.ml"; "string.ml"; "bytes.ml"; "buffer.ml"; "printf.ml"; "format.ml"
    ; "either.ml"; "result.ml"; "lazy.ml"; "std_exit.ml"; "listLabels.ml"; "arrayLabels.ml"
    ]
;;

let site (s : Signal.t) =
  let rec atoms (x : Sexp.t) =
    match x with
    | Atom a -> [ a ]
    | List l -> List.concat_map l ~f:atoms
  in
  let ours a =
    String.contains a ':'
    && (not (String.is_prefix a ~prefix:"src/"))
    && (not (String.is_prefix a ~prefix:"hardcaml_latency/"))
    && (not (String.is_prefix a ~prefix:"latency_ci/"))
    && (not (String.is_prefix a ~prefix:"camlinternal"))
    &&
    match String.lsplit2 a ~on:':' with
    | Some (file, _) -> not (Set.mem stdlib_files file)
    | None -> false
  in
  match Signal.Type.caller_id s with
  | None -> None
  | Some c -> List.find (atoms (Caller_id.sexp_of_t c)) ~f:ours
;;

(* Rewrite " (uid N)[ @ file:l:c]" as " @ <site of N>", so that the text depends neither on
   uids (which change with every edit) nor on the lint's narrower choice of frame. *)
let relocate ~site_of s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let is_digit c = Char.is_digit c in
  let rec skip_digits j = if j < n && is_digit s.[j] then skip_digits (j + 1) else j in
  (* after "(uid N)": skip an existing " @ path:line:col" *)
  let skip_site j =
    if String.is_substring_at s ~pos:j ~substring:" @ "
    then (
      match String.index_from s (j + 3) ':' with
      | None -> j
      | Some k ->
        let k = skip_digits (k + 1) in
        if k < n && Char.equal s.[k] ':' then skip_digits (k + 1) else k)
    else j
  in
  let rec go i =
    if i >= n
    then ()
    else if String.is_substring_at s ~pos:i ~substring:" (uid "
    then (
      match String.index_from s (i + 6) ')' with
      | None -> Buffer.add_substring b s ~pos:i ~len:(n - i)
      | Some j ->
        let uid = String.sub s ~pos:(i + 6) ~len:(j - i - 6) in
        (match site_of uid with
         | Some st -> Buffer.add_string b (" @ " ^ st)
         | None -> ());
        go (skip_site (j + 1)))
    else (
      Buffer.add_char b s.[i];
      go (i + 1))
  in
  go 0;
  Buffer.contents b
;;

let site_table circuit =
  let t = Hashtbl.create (module String) in
  Signal_graph.iter (Circuit.signal_graph circuit) ~f:(fun s ->
    Hashtbl.set t ~key:(Signal.Type.Uid.to_string (Signal.uid s)) ~data:(site s));
  fun uid -> Option.join (Hashtbl.find t uid)
;;

type config =
  { hold_registers : bool
  ; check_enables : bool
  }

let default = { hold_registers = false; check_enables = false }
let hold = { hold_registers = true; check_enables = false }

let config_name c =
  match c.hold_registers, c.check_enables with
  | false, false -> "defaults"
  | true, false -> "hold_registers"
  | false, true -> "check_enables"
  | true, true -> "hold_registers, check_enables"
;;

type linted =
  { result : Latency_lint.result
  ; site_of : string -> string option
  }

let lint ?(config = default) circuit =
  { result =
      Latency_lint.check_circuit
        ~hold_registers:config.hold_registers
        ~check_enables:config.check_enables
        circuit
  ; site_of = site_table circuit
  }
;;

let normalise l f = relocate ~site_of:l.site_of (Latency_lint.to_string f)

let failures = ref 0

(* Diagnostics that vary with unrelated edits go to stderr, and only with LATENCY_VERBOSE set,
   so that a passing [dune test] stays quiet. *)
let verbose = Option.is_some (Sys.getenv "LATENCY_VERBOSE")
let diag fmt = Printf.ksprintf (fun s -> if verbose then Stdio.eprintf "%s%!" s) fmt

let fail fmt =
  Printf.ksprintf
    (fun s ->
      Int.incr failures;
      Stdio.eprintf "FAIL: %s\n%!" s)
    fmt
;;

(* Print one design's findings for the expected file. The node counts go to stderr: they
   change with every edit, so they do not belong in the compared output, but a run that
   checked nothing is a failure, not a clean pass. *)
let print ~title ?(config = default) l =
  let r = l.result in
  Stdio.printf "== %s (%s): %d finding(s)\n" title (config_name config) (List.length r.findings);
  diag
    "%s: %d of %d nodes checked; %d loop registers; %d memories/instances cut\n"
    title
    r.checked
    r.nodes
    r.loop_registers
    r.cut_boundaries;
  if r.checked = 0 then fail "%s: the lint checked no node at all" title;
  List.map r.findings ~f:(normalise l)
  |> List.sort ~compare:String.compare
  |> List.iter ~f:Stdio.print_endline
;;

(* The planted control must add at least one finding that the real design does not have. *)
let expect_caught ~title ~real ~planted =
  let real_set =
    Set.of_list (module String) (List.map real.result.findings ~f:(normalise real))
  in
  let fresh =
    List.filter planted.result.findings ~f:(fun f ->
      not (Set.mem real_set (normalise planted f)))
  in
  Stdio.printf
    "== planted control, %s: %d new finding(s) -> %s\n"
    title
    (List.length fresh)
    (if List.is_empty fresh then "NOT CAUGHT" else "caught");
  if List.is_empty fresh then fail "planted control %s was not caught by the lint" title
;;

let exit () = if !failures > 0 then Stdlib.exit 1
