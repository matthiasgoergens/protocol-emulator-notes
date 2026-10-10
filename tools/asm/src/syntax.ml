(* One source line: labels, then an assignment, an instruction, a macro call or a directive, each
   with comma-separated arguments. An argument is positional or "name=value". *)

open Lexer

type arg =
  | Pos of tok list
  | Kw of string * tok list

type stmt =
  | Empty
  | Assign of string * tok list                  (* NAME = expr *)
  | Call of string * arg list                    (* mnemonic, macro or .directive *)

type line = { labels : string list; stmt : stmt }

(* split at commas outside parentheses and brackets *)
let split_commas toks =
  let rec go depth cur acc = function
    | [] -> List.rev (List.rev cur :: acc)
    | (Op ("(" | "[") as t) :: r -> go (depth + 1) (t :: cur) acc r
    | (Op (")" | "]") as t) :: r -> go (depth - 1) (t :: cur) acc r
    | Op "," :: r when depth = 0 -> go depth [] (List.rev cur :: acc) r
    | t :: r -> go depth (t :: cur) acc r in
  match toks with [] -> [] | _ -> go 0 [] [] toks

let arg_of loc = function
  | [] -> Loc.error loc "empty argument (two commas in a row?)"
  | Ident k :: Op "=" :: v when k <> "." && k.[0] <> '.' ->
    if v = [] then Loc.error loc "%s= needs a value" k;
    Kw (k, v)
  | toks -> Pos toks

let parse loc text =
  let toks = Lexer.tokens loc text in
  let rec labels acc = function
    | Ident l :: Op ":" :: r when l.[0] <> '.' -> labels (l :: acc) r
    | r -> List.rev acc, r in
  let ls, rest = labels [] toks in
  let stmt =
    match rest with
    | [] -> Empty
    | Ident n :: Op "=" :: v when n.[0] <> '.' -> Assign (n, v)
    | Ident n :: args ->
      let args = List.map (arg_of loc) (split_commas args) in
      let keys = List.filter_map (function Kw (k, _) -> Some k | Pos _ -> None) args in
      List.iter (fun k -> if List.length (List.filter (( = ) k) keys) > 1 then Loc.error loc "%s= given twice" k) keys;
      Call (n, args)
    | t :: _ -> Loc.error loc "a line starts with a label, a name or a directive, not %s" (Lexer.to_string t)
  in
  { labels = ls; stmt }

(* the head of a raw line, for block structure (.macro, .rep, .if) before substitution *)
let head text =
  let t = String.trim (Lexer.strip_comment text) in
  let n = String.length t in
  let i = ref 0 in
  (* skip labels "name:" *)
  let rec skip_labels () =
    let j = ref !i in
    while !j < n && Lexer.is_ident_char t.[!j] do incr j done;
    if !j > !i && !j < n && t.[!j] = ':' then begin
      i := !j + 1;
      while !i < n && (t.[!i] = ' ' || t.[!i] = '\t') do incr i done;
      skip_labels ()
    end in
  skip_labels ();
  let j = ref !i in
  if !j < n && t.[!j] = '.' then incr j;
  while !j < n && Lexer.is_ident_char t.[!j] do incr j done;
  let h = String.sub t !i (!j - !i) in
  let rest = String.trim (String.sub t !j (n - !j)) in
  h, rest

let toks_to_string toks = String.concat " " (List.map Lexer.to_string toks)
