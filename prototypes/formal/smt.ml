(* SMT-LIB terms for the symbolic instance of the interpreter, and a solver over a pipe.

   Terms are hash-consed (one node per distinct term) and folded when they are built: operations
   on constants are evaluated, and the usual identities (x and false, ite with a constant
   condition, equal branches, ...) are applied. The programme is concrete, so most of a clock's
   arithmetic folds away and only what depends on inputs reaches the solver.

   Emission is lazy: [Solver.assert_] writes, at the top level, a (define-fun ...) for every node
   the asserted term needs that has not been written yet. Definitions are never written inside a
   push, so pop never discards one. *)

type sort = Bool | Bv of int | Mem   (* Mem: the data bank, (Array (_ BitVec 10) (_ BitVec 8)) *)

type term = { id : int; sort : sort; node : node }
and node =
  | Var of string
  | B of bool
  | K of int                          (* bit-vector constant *)
  | App of string * int list * term list   (* SMT-LIB operator, indices, arguments *)

let width t = match t.sort with Bv w -> w | Bool -> invalid_arg "width of a Bool" | Mem -> invalid_arg "width of a Mem"
let mask w = if w >= Sys.int_size - 1 then -1 else (1 lsl w) - 1

(* hash-consing *)
type key = KVar of string | KB of bool | KK of int * int | KApp of string * int list * int list
let table : (key, term) Hashtbl.t = Hashtbl.create 100_000
let next_id = ref 0
let nodes_built () = !next_id

let mk key sort node =
  match Hashtbl.find_opt table key with
  | Some t -> t
  | None -> let t = { id = !next_id; sort; node } in incr next_id; Hashtbl.add table key t; t

let var name sort = mk (KVar name) sort (Var name)
let b v = mk (KB v) Bool (B v)
let tt = b true and ff = b false
let k ~w n = let n = n land mask w in mk (KK (w, n)) (Bv w) (K n)
let app op idx args sort = mk (KApp (op, idx, List.map (fun a -> a.id) args)) sort (App (op, idx, args))

let is_k t = match t.node with K _ -> true | _ -> false
let kval t = match t.node with K n -> n | _ -> invalid_arg "kval"
let bval t = match t.node with B v -> Some v | _ -> None

(* ---- Booleans ---- *)
let not_ x =
  match x.node with
  | B v -> b (not v)
  | App ("not", _, [ y ]) -> y
  | _ -> app "not" [] [ x ] Bool

let and_ x y =
  match x.node, y.node with
  | B false, _ | _, B false -> ff
  | B true, _ -> y
  | _, B true -> x
  | _ when x == y -> x
  | _ when not_ x == y -> ff
  | _ -> app "and" [] [ x; y ] Bool

let or_ x y =
  match x.node, y.node with
  | B true, _ | _, B true -> tt
  | B false, _ -> y
  | _, B false -> x
  | _ when x == y -> x
  | _ when not_ x == y -> tt
  | _ -> app "or" [] [ x; y ] Bool

let ite_bool s x y =
  match s.node, x.node, y.node with
  | B true, _, _ -> x
  | B false, _, _ -> y
  | _ when x == y -> x
  | _, B true, B false -> s
  | _, B false, B true -> not_ s
  | _, _, B false -> and_ s x
  | _, B true, _ -> or_ s y
  | _, B false, _ -> and_ (not_ s) y
  | _, _, B true -> or_ (not_ s) x
  | _ -> app "ite" [] [ s; x; y ] Bool

(* ---- bit-vectors ---- *)
let same_width x y = if width x <> width y then invalid_arg (Printf.sprintf "width %d vs %d" (width x) (width y))

let ite s x y =
  match s.node with
  | B true -> x
  | B false -> y
  | _ ->
    if x == y then x
    else begin
      if x.sort <> y.sort then invalid_arg "ite: sorts differ";
      match x.sort with
      | Bool -> ite_bool s x y
      | _ -> (match s.node with App ("not", _, [ s' ]) -> app "ite" [] [ s'; y; x ] x.sort | _ -> app "ite" [] [ s; x; y ] x.sort)
    end

let rec eq x y =
  same_width x y;
  if x == y then tt
  else match x.node, y.node with
    | K a, K c -> b (a = c)
    (* a comparison of a tree of constants with a constant folds to a condition on the tree *)
    | App ("ite", _, [ s; p; q ]), K _ when (is_k p || is_ite p) && (is_k q || is_ite q) -> ite_bool s (eq p y) (eq q y)
    | K _, App ("ite", _, _) -> eq y x
    | _ -> if x.id < y.id then app "=" [] [ x; y ] Bool else app "=" [] [ y; x ] Bool
and is_ite t = match t.node with App ("ite", _, _) -> true | _ -> false

let binop op f ~unit_ ~zero x y =
  same_width x y;
  let w = width x in
  match x.node, y.node with
  | K a, K c -> k ~w (f a c)
  | _ ->
    let is v t = match t.node with K n -> n = v land mask w | _ -> false in
    match unit_, zero with
    | Some u, _ when is u y -> x
    | Some u, _ when is u x -> y
    | _, Some z when is z x || is z y -> k ~w z
    | _ -> if op <> "bvsub" && x.id > y.id then app op [] [ y; x ] x.sort else app op [] [ x; y ] x.sort

let add ~w x y = assert (width x = w); binop "bvadd" ( + ) ~unit_:(Some 0) ~zero:None x y
let sub ~w x y =
  assert (width x = w); same_width x y;
  match x.node, y.node with
  | K a, K c -> k ~w (a - c)
  | _, K 0 -> x
  | _ -> app "bvsub" [] [ x; y ] x.sort
let logand x y = if x == y then x else binop "bvand" ( land ) ~unit_:(Some (-1)) ~zero:(Some 0) x y
let logor x y = if x == y then x else binop "bvor" ( lor ) ~unit_:(Some 0) ~zero:(Some (-1)) x y
let logxor x y = binop "bvxor" ( lxor ) ~unit_:(Some 0) ~zero:None x y
let lognot ~w x = assert (width x = w); match x.node with K a -> k ~w (lnot a) | _ -> app "bvnot" [] [ x ] x.sort

let shl ~w x s =
  assert (width x = w); same_width x s;
  match x.node, s.node with
  | K a, K n -> k ~w (if n >= w then 0 else a lsl n)
  | _, K 0 -> x
  | K 0, _ -> x
  | _ -> app "bvshl" [] [ x; s ] x.sort

let lshr x s =
  same_width x s;
  let w = width x in
  match x.node, s.node with
  | K a, K n -> k ~w (if n >= w then 0 else a lsr n)
  | _, K 0 -> x
  | K 0, _ -> x
  | _ -> app "bvlshr" [] [ x; s ] x.sort

let ult x y =
  same_width x y;
  match x.node, y.node with
  | K a, K c -> b (a < c)
  | _, K 0 -> ff
  | _ -> app "bvult" [] [ x; y ] Bool

let rec extract x ~hi ~lo =
  let w = width x in
  assert (0 <= lo && lo <= hi && hi < w);
  if lo = 0 && hi = w - 1 then x
  else match x.node with
    | K a -> k ~w:(hi - lo + 1) (a lsr lo)
    | App ("extract", [ _; lo' ], [ y ]) -> extract y ~hi:(hi + lo') ~lo:(lo + lo')
    | App ("zero_extend", [ _ ], [ y ]) ->
      let wy = width y in
      if hi < wy then extract y ~hi ~lo
      else if lo >= wy then k ~w:(hi - lo + 1) 0
      else app "extract" [ hi; lo ] [ x ] (Bv (hi - lo + 1))
    | App ("ite", _, [ s; p; q ]) when is_k p && is_k q -> ite s (extract p ~hi ~lo) (extract q ~hi ~lo)
    | _ -> app "extract" [ hi; lo ] [ x ] (Bv (hi - lo + 1))

let zext ~w x =
  let wx = width x in
  assert (w >= wx);
  if w = wx then x
  else match x.node with
    | K a -> k ~w a
    | _ -> app "zero_extend" [ w - wx ] [ x ] (Bv w)

(* ---- the data bank ---- *)
let mem_var name = var name Mem
let mem_zero () = app "const-array" [] [] Mem   (* every byte 0 *)
let rec select m a =
  assert (m.sort = Mem && width a = 10);
  match m.node, a.node with
  | App ("const-array", _, []), _ -> k ~w:8 0
  | App ("store", _, [ m'; a'; v ]), K x when is_k a' -> if kval a' = x then v else select m' a
  | _ -> app "select" [] [ m; a ] (Bv 8)
let store m a v = assert (width v = 8); app "store" [] [ m; a; v ] Mem
let mem_ite s x y = match s.node with B true -> x | B false -> y | _ -> if x == y then x else app "ite" [] [ s; x; y ] Mem

(* The interpreter's value domain (Isa2.VALUE). *)
module Value = struct
  type t = term
  type b = term
  type mem = term
  let const ~w n = k ~w n
  let add = add
  let sub = sub
  let logand = logand
  let logor = logor
  let logxor = logxor
  let lognot = lognot
  let shl = shl
  let lshr = lshr
  let extract = extract
  let zext = zext
  let eq = eq
  let ult = ult
  let ite = ite
  let tt = tt
  let ff = ff
  let not_ = not_
  let and_ = and_
  let or_ = or_
  let mem_read = select
  let mem_write m s a v = mem_ite s (store m a v) m
  let mem_ite = mem_ite
  let mem_copy m = m
end

(* ---- SMT-LIB text ---- *)
let sort_text = function
  | Bool -> "Bool"
  | Bv w -> Printf.sprintf "(_ BitVec %d)" w
  | Mem -> "(Array (_ BitVec 10) (_ BitVec 8))"

let name t =
  match t.node with
  | Var n -> n
  | B v -> string_of_bool v
  | K n -> Printf.sprintf "(_ bv%d %d)" n (width t)
  | App _ -> Printf.sprintf "t%d" t.id

let app_text op idx args =
  let a = String.concat " " (List.map name args) in
  if op = "const-array" then "((as const (Array (_ BitVec 10) (_ BitVec 8))) (_ bv0 8))" else
  match idx with
  | [] -> Printf.sprintf "(%s %s)" op a
  | _ -> Printf.sprintf "((_ %s %s) %s)" op (String.concat " " (List.map string_of_int idx)) a

(* ---- the solver process ---- *)
module Solver = struct
  type t = {
    oc : out_channel; ic : in_channel;
    emitted : (int, unit) Hashtbl.t;
    log : out_channel option;     (* a copy of everything sent, replayable with z3 -smt2 FILE *)
    mutable defs : int;
    mutable vars : term list;     (* every variable declared so far *)
  }

  let solver_command () =
    match Sys.getenv_opt "SMT_SOLVER" with Some s -> s | None -> "z3"

  let send s text =
    output_string s.oc text; output_char s.oc '\n';
    (match s.log with Some l -> output_string l text; output_char l '\n' | None -> ())

  let start ?log () =
    let cmd = solver_command () in
    let ic, oc = Unix.open_process_args cmd [| cmd; "-in"; "-smt2" |] in
    let s = { oc; ic; emitted = Hashtbl.create 100_000; log = Option.map open_out log; defs = 0; vars = [] } in
    send s "(set-option :produce-models true)";
    send s "(set-logic QF_ABV)";
    s

  (* write the definitions of [t] and everything under it, children first, without recursion
     on the OCaml stack (terms built over hundreds of clocks are deep) *)
  let ensure s t =
    let stack = ref [ (t, false) ] in
    while !stack <> [] do
      match !stack with
      | [] -> ()
      | (u, expanded) :: rest ->
        stack := rest;
        if not (Hashtbl.mem s.emitted u.id) then begin
          match u.node with
          | B _ | K _ -> Hashtbl.replace s.emitted u.id ()
          | Var n ->
            Hashtbl.replace s.emitted u.id ();
            s.vars <- u :: s.vars;
            send s (Printf.sprintf "(declare-const %s %s)" n (sort_text u.sort))
          | App (op, idx, args) ->
            if expanded then begin
              Hashtbl.replace s.emitted u.id ();
              s.defs <- s.defs + 1;
              send s (Printf.sprintf "(define-fun t%d () %s %s)" u.id (sort_text u.sort) (app_text op idx args))
            end else
              stack := List.map (fun a -> (a, false)) args @ ((u, true) :: !stack)
        end
    done

  let assert_ s t = assert (t.sort = Bool); ensure s t; send s (Printf.sprintf "(assert %s)" (name t))
  let push s = send s "(push 1)"
  let pop s = send s "(pop 1)"

  let check s =
    send s "(check-sat)"; flush s.oc;
    match String.trim (input_line s.ic) with
    | "sat" -> `Sat | "unsat" -> `Unsat
    | r -> `Unknown r

  (* a minimal s-expression reader for (get-value ...) replies *)
  type sexp = Atom of string | List of sexp list

  let read_sexp ic =
    let buf = Buffer.create 256 in
    let depth = ref 0 and started = ref false in
    while not (!started && !depth = 0) do
      let ch = input_char ic in
      if ch = '(' then (incr depth; started := true)
      else if ch = ')' then decr depth;
      if !started then Buffer.add_char buf ch
    done;
    let s = Buffer.contents buf in
    let pos = ref 0 and n = String.length s in
    let rec parse () =
      while !pos < n && (s.[!pos] = ' ' || s.[!pos] = '\n' || s.[!pos] = '\t' || s.[!pos] = '\r') do incr pos done;
      if s.[!pos] = '(' then begin
        incr pos;
        let items = ref [] in
        let fin = ref false in
        while not !fin do
          while !pos < n && (s.[!pos] = ' ' || s.[!pos] = '\n' || s.[!pos] = '\t' || s.[!pos] = '\r') do incr pos done;
          if s.[!pos] = ')' then (incr pos; fin := true) else items := parse () :: !items
        done;
        List (List.rev !items)
      end else begin
        let st = !pos in
        while !pos < n && not (List.mem s.[!pos] [ ' '; '\n'; '\t'; '\r'; '('; ')' ]) do incr pos done;
        Atom (String.sub s st (!pos - st))
      end in
    parse ()

  let value_of = function
    | Atom "true" -> 1
    | Atom "false" -> 0
    | Atom a when String.length a > 2 && String.sub a 0 2 = "#b" -> int_of_string ("0b" ^ String.sub a 2 (String.length a - 2))
    | Atom a when String.length a > 2 && String.sub a 0 2 = "#x" -> int_of_string ("0x" ^ String.sub a 2 (String.length a - 2))
    | List [ Atom "_"; Atom bv; Atom _ ] when String.length bv > 2 -> int_of_string (String.sub bv 2 (String.length bv - 2))
    | _ -> failwith "unexpected model value"

  (* model values of bit-vector or Bool terms (already emitted), as integers *)
  let get_values s terms =
    if terms = [] then []
    else begin
      send s (Printf.sprintf "(get-value (%s))" (String.concat " " (List.map name terms))); flush s.oc;
      match read_sexp s.ic with
      | List pairs -> List.map2 (fun t p -> match p with List [ _; v ] -> (t, value_of v) | _ -> failwith "get-value") terms pairs
      | Atom a -> failwith ("get-value: " ^ a)
    end

  let close s =
    send s "(exit)"; flush s.oc;
    ignore (Unix.close_process (s.ic, s.oc));
    Option.iter close_out s.log
end
