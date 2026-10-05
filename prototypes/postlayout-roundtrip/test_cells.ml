(* Two sources for the same cell functions must agree: the PDK's Verilog
   models, as interpreted by Cells (what the simulator uses), and the
   liberty "function", "next_state", "clear" and "preset" strings (what
   synthesis mapped against).  Every pin of every cell, exhaustively over its
   inputs.  This guards the Verilog interpreter: one entrant's model of the
   puzzle chip reproduced the sample waveform with every tie-high cell wrong.

   test_cells.exe MODELS.v LIBERTY.lib *)

(* ---- liberty boolean expressions: ! and postfix ' (not), ^ (xor),
   * & or juxtaposition (and), + | (or), parentheses, 0 and 1 ---- *)

type e = V of string | C of int | N of e | A of e * e | O of e * e | X of e * e

let parse_expr (s : string) : e =
  let n = String.length s in
  let i = ref 0 in
  let rec ws () = if !i < n && (s.[!i] = ' ' || s.[!i] = '\t') then (incr i; ws ()) in
  let peek () = ws (); if !i < n then Some s.[!i] else None in
  let rec orx () =
    let l = ref (andx ()) in
    while (match peek () with Some ('+' | '|') -> true | _ -> false) do incr i; l := O (!l, andx ()) done;
    !l
  and andx () =
    let l = ref (xorx ()) in
    let continue = ref true in
    while !continue do
      match peek () with
      | Some ('*' | '&') -> incr i; l := A (!l, xorx ())
      | Some ('(' | '!' | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '1') -> l := A (!l, xorx ())
      | _ -> continue := false
    done;
    !l
  and xorx () =
    let l = ref (unary ()) in
    while peek () = Some '^' do incr i; l := X (!l, unary ()) done;
    !l
  and unary () =
    match peek () with
    | Some '!' -> incr i; N (unary ())
    | _ -> postfix (atom ())
  and postfix a = if peek () = Some '\'' then (incr i; postfix (N a)) else a
  and atom () =
    match peek () with
    | Some '(' -> incr i; let r = orx () in ignore (peek ()); incr i; r
    | Some ('0' | '1' as c) -> incr i; C (Char.code c - 48)
    | Some _ ->
      let j = !i in
      while !i < n && (match s.[!i] with 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true | _ -> false) do incr i done;
      if !i = j then failwith ("liberty expression: " ^ s);
      V (String.sub s j (!i - j))
    | None -> failwith ("liberty expression ends early: " ^ s)
  in
  let r = orx () in
  if peek () <> None then failwith ("liberty expression: trailing text in " ^ s);
  r

let rec eval env = function
  | V v -> (match List.assoc_opt v env with Some x -> x | None -> failwith ("unbound " ^ v))
  | C c -> c
  | N a -> 1 - eval env a
  | A (a, b) -> eval env a land eval env b
  | O (a, b) -> eval env a lor eval env b
  | X (a, b) -> eval env a lxor eval env b

(* ---- liberty: per cell, pin functions and the ff group ---- *)

type lcell = { mutable funcs : (string * string) list; mutable ff : (string * string) list }

let between s a b =
  match String.index_opt s a with
  | None -> None
  | Some i ->
    (match String.index_from_opt s (i + 1) b with
     | Some j -> Some (String.sub s (i + 1) (j - i - 1))
     | None -> None)

let unquote s = String.trim s |> String.split_on_char '"' |> String.concat ""

let parse_liberty path =
  let ic = open_in path in
  let cells = Hashtbl.create 100 in
  let cur = ref None and pin = ref "" and in_ff = ref false in
  (try
     while true do
       let l = String.trim (input_line ic) in
       let starts p = String.starts_with ~prefix:p l in
       if starts "cell (" || starts "cell(" then begin
         let name = unquote (Option.get (between l '(' ')')) in
         let c = { funcs = []; ff = [] } in
         Hashtbl.replace cells name c;
         cur := Some c; in_ff := false
       end
       (* a scan flip-flop's test_cell (at the end of its cell group) describes
          the non-scan view; it is not the cell's function *)
       else if starts "test_cell" then cur := None
       else if starts "pin (" || starts "pin(" then (pin := unquote (Option.get (between l '(' ')')); in_ff := false)
       else if starts "ff (" || starts "ff(" then in_ff := true
       else
         match !cur, String.index_opt l ':' with
         | Some c, Some k ->
           let key = String.trim (String.sub l 0 k) in
           let v = String.sub l (k + 1) (String.length l - k - 1) in
           let v = unquote (if String.ends_with ~suffix:";" v then String.sub v 0 (String.length v - 1) else v) in
           if key = "function" then c.funcs <- (!pin, v) :: c.funcs
           else if !in_ff && List.mem key [ "next_state"; "clear"; "preset"; "clocked_on" ] then
             c.ff <- (key, v) :: c.ff
         | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  cells

(* ---- evaluating a Verilog model ---- *)

let run_model (c : Cells.cell) env q =
  let w = Hashtbl.create 16 in
  Hashtbl.replace w "1'b0" 0;
  Hashtbl.replace w "1'b1" 1;
  List.iter (fun (k, v) -> Hashtbl.replace w k v) env;
  List.iter (fun (f : Cells.ff) -> Hashtbl.replace w f.q q) c.ffs;
  Array.iter (fun (g : Cells.gate) ->
    Hashtbl.replace w g.gout (Cells.eval_prim g.gprim (Array.map (Hashtbl.find w) g.gins))) c.gates;
  w

let () =
  let models = Cells.parse_library Sys.argv.(1) in
  let lib = parse_liberty Sys.argv.(2) in
  let checked = ref 0 and failures = ref 0 and skipped = ref [] in
  let fail fmt = Printf.ksprintf (fun s -> incr failures; if !failures <= 20 then print_endline ("FAIL " ^ s)) fmt in
  Hashtbl.iter (fun name (lc : lcell) ->
    match Hashtbl.find_opt models name with
    | None -> skipped := (name ^ " (no model)") :: !skipped
    | Some { unsupported = Some why; _ } -> skipped := (name ^ " (" ^ why ^ ")") :: !skipped
    | Some m ->
      let ins = m.inputs in
      let nin = List.length ins in
      for bits = 0 to (1 lsl nin) - 1 do
        let env = List.mapi (fun i p -> (p, (bits lsr i) land 1)) ins in
        List.iter (fun q ->
          let w = run_model m env q in
          let env' = ("IQ", q) :: ("IQN", 1 - q) :: env in
          List.iter (fun (pin, f) ->
            incr checked;
            let want = eval env' (parse_expr f) in
            match Hashtbl.find_opt w pin with
            | Some got when got = want -> ()
            | got -> fail "%s.%s = %s for %s IQ=%d: model gives %s" name pin f
                       (String.concat "," (List.map (fun (p, v) -> p ^ "=" ^ string_of_int v) env)) q
                       (match got with Some g -> string_of_int g | None -> "nothing"))
            lc.funcs;
          match m.ffs, lc.ff with
          | [], [] -> ()
          | [ f ], ffl ->
            List.iter (fun (key, expr) ->
              let wire = match key with
                | "next_state" -> Some f.d | "clear" -> f.r | "preset" -> f.s | "clocked_on" -> Some f.clk
                | _ -> None in
              incr checked;
              let want = eval env' (parse_expr expr) in
              match wire with
              | Some wn when Hashtbl.find_opt w wn = Some want -> ()
              | _ -> fail "%s ff %s = %s disagrees with the model" name key expr)
              ffl;
            (* a model with reset or set the liberty does not have, or back *)
            if (f.r <> None) <> List.mem_assoc "clear" ffl || (f.s <> None) <> List.mem_assoc "preset" ffl then
              fail "%s: set/reset pins differ between model and liberty" name
          | _ -> fail "%s: flip-flop structure differs" name)
          (if m.ffs = [] then [ 0 ] else [ 0; 1 ])
      done) lib;
  List.iter (fun s -> Printf.printf "skipped %s\n" s) (List.sort compare !skipped);
  Printf.printf "cells: %d comparisons, %d disagreements\n" !checked !failures;
  exit (if !failures = 0 then 0 else 1)
