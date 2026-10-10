(* Constant expressions: integers, symbols, '.' (the current pc), C-like operators and a few
   functions. Evaluated with arbitrary-width OCaml integers; each operand position checks its own
   range. *)

open Lexer

type t =
  | Int of int
  | Sym of string
  | Here                                   (* '.' *)
  | Un of string * t
  | Bin of string * t * t
  | Call of string * t list

(* operators by precedence, loosest first *)
let levels = [ [ "||" ]; [ "&&" ]; [ "|" ]; [ "^" ]; [ "&" ]; [ "=="; "!=" ]; [ "<"; "<="; ">"; ">=" ];
               [ "<<"; ">>" ]; [ "+"; "-" ]; [ "*"; "/"; "%" ] ]

let functions = [ "lo"; "hi"; "page"; "pc"; "addr"; "min"; "max"; "bit" ]

(* parse a whole token list as one expression *)
let parse loc (toks : tok list) =
  let toks = ref toks in
  let peek () = match !toks with t :: _ -> Some t | [] -> None in
  let advance () = match !toks with _ :: r -> toks := r | [] -> () in
  let expect s = match peek () with
    | Some (Op o) when o = s -> advance ()
    | Some t -> Loc.error loc "expected %s in expression, found %s" s (Lexer.to_string t)
    | None -> Loc.error loc "expected %s at the end of an expression" s in
  let rec level = function
    | [] -> unary ()
    | ops :: tighter ->
      let lhs = ref (level tighter) in
      let rec loop () =
        match peek () with
        | Some (Op o) when List.mem o ops -> advance (); lhs := Bin (o, !lhs, level tighter); loop ()
        | _ -> () in
      loop (); !lhs
  and unary () =
    match peek () with
    | Some (Op ("-" | "~" | "!" as o)) -> advance (); Un (o, unary ())
    | Some (Op "+") -> advance (); unary ()
    | _ -> primary ()
  and primary () =
    match peek () with
    | Some (Num n) -> advance (); Int n
    | Some (Ident ".") -> advance (); Here
    | Some (Ident f) when List.mem f functions && (match !toks with _ :: Op "(" :: _ -> true | _ -> false) ->
      advance (); advance ();
      let args = ref [ level levels ] in
      let rec more () = match peek () with
        | Some (Op ",") -> advance (); args := level levels :: !args; more ()
        | _ -> () in
      more (); expect ")";
      Call (f, List.rev !args)
    | Some (Ident s) when s.[0] <> '.' -> advance (); Sym s
    | Some (Op "(") -> advance (); let e = level levels in expect ")"; e
    | Some t -> Loc.error loc "unexpected %s in expression" (Lexer.to_string t)
    | None -> Loc.error loc "missing expression"
  in
  let e = level levels in
  (match !toks with
   | [] -> ()
   | t :: _ -> Loc.error loc "unexpected %s after expression" (Lexer.to_string t));
  e

(* what the evaluator needs from the assembler *)
type env = {
  lookup : string -> int option;              (* a constant, or a label's pc *)
  label : string -> (int * int) option;       (* a label's (page, pc) *)
  here : unit -> int;                         (* the current pc *)
}

let rec eval loc env e =
  let ev = eval loc env in
  let bool b = if b then 1 else 0 in
  match e with
  | Int n -> n
  | Here -> env.here ()
  | Sym s -> (match env.lookup s with Some v -> v | None -> Loc.error loc "undefined symbol %s" s)
  | Un ("-", a) -> - ev a
  | Un ("~", a) -> lnot (ev a)
  | Un ("!", a) -> bool (ev a = 0)
  | Un (o, _) -> Loc.error loc "unknown operator %s" o
  | Bin (o, a, b) ->
    let x = ev a and y = ev b in
    (match o with
     | "+" -> x + y | "-" -> x - y | "*" -> x * y
     | "/" -> if y = 0 then Loc.error loc "division by zero" else x / y
     | "%" -> if y = 0 then Loc.error loc "division by zero" else x mod y
     | "<<" -> x lsl y | ">>" -> x asr y
     | "&" -> x land y | "|" -> x lor y | "^" -> x lxor y
     | "==" -> bool (x = y) | "!=" -> bool (x <> y)
     | "<" -> bool (x < y) | "<=" -> bool (x <= y) | ">" -> bool (x > y) | ">=" -> bool (x >= y)
     | "&&" -> bool (x <> 0 && y <> 0) | "||" -> bool (x <> 0 || y <> 0)
     | _ -> Loc.error loc "unknown operator %s" o)
  | Call ("lo", [ a ]) -> ev a land 0xFF
  | Call ("hi", [ a ]) -> (ev a lsr 8) land 0xFF
  | Call ("min", [ a; b ]) -> min (ev a) (ev b)
  | Call ("max", [ a; b ]) -> max (ev a) (ev b)
  | Call ("bit", [ a ]) -> 1 lsl ev a
  | Call (("page" | "pc" | "addr") as f, [ Sym l ]) ->
    (match env.label l with
     | Some (pg, pc) -> (match f with "page" -> pg | "pc" -> pc | _ -> (pg lsl 8) lor pc)
     | None -> Loc.error loc "%s(%s): %s is not a label" f l l)
  | Call (f, args) -> Loc.error loc "%s takes a different number of arguments (got %d)" f (List.length args)

let rec to_string = function
  | Int n -> string_of_int n
  | Sym s -> s
  | Here -> "."
  | Un (o, a) -> o ^ to_string a
  | Bin (o, a, b) -> "(" ^ to_string a ^ " " ^ o ^ " " ^ to_string b ^ ")"
  | Call (f, a) -> f ^ "(" ^ String.concat ", " (List.map to_string a) ^ ")"
