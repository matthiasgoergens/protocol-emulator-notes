(* Tokens of one source line. Comments run from ';' to the end of the line. *)

type tok =
  | Ident of string        (* names, mnemonics, ".directives", and "." (the current pc) *)
  | Num of int             (* decimal, 0x, 0b, 0o, '_' separators, and 'c' character literals *)
  | Str of string          (* "..." *)
  | Op of string           (* punctuation and operators *)

let to_string = function
  | Ident s -> s
  | Num n -> string_of_int n
  | Str s -> Printf.sprintf "%S" s
  | Op s -> s

let is_ident_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_ident_char c = is_ident_start c || (c >= '0' && c <= '9')
let is_digit c = c >= '0' && c <= '9'

let two_char_ops = [ "<<"; ">>"; "=="; "!="; "<="; ">="; "&&"; "||"; ".." ]
let one_char_ops = "+-*/%&|^~!(),=:<>[]@#"

(* the text of a line without its comment; ';' inside strings and character literals is kept *)
let strip_comment s =
  let n = String.length s in
  let rec go i in_str =
    if i >= n then s
    else
      match s.[i] with
      | '"' -> go (i + 1) (not in_str)
      | '\\' when in_str -> go (i + 2) in_str
      | '\'' when (not in_str) && i + 2 < n && s.[i + 2] = '\'' -> go (i + 3) in_str
      | ';' when not in_str -> String.sub s 0 i
      | _ -> go (i + 1) in_str
  in
  go 0 false

let tokens loc s =
  let s = strip_comment s in
  let n = String.length s in
  let out = ref [] in
  let push t = out := t :: !out in
  let i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    if c = ' ' || c = '\t' || c = '\r' then incr i
    else if is_ident_start c || (c = '.' && !i + 1 < n && is_ident_start s.[!i + 1]) then begin
      let j = ref (!i + 1) in
      while !j < n && is_ident_char s.[!j] do incr j done;
      push (Ident (String.sub s !i (!j - !i)));
      i := !j
    end
    else if is_digit c then begin
      let j = ref !i in
      while !j < n && (is_ident_char s.[!j]) do incr j done;
      let text = String.sub s !i (!j - !i) in
      let clean = String.concat "" (String.split_on_char '_' text) in
      let v =
        try
          if String.length clean > 2 && clean.[0] = '0' then
            match clean.[1] with
            | 'x' | 'X' | 'b' | 'B' | 'o' | 'O' -> int_of_string clean
            | _ -> int_of_string clean
          else int_of_string clean
        with Failure _ -> Loc.error loc "malformed number %S" text
      in
      push (Num v);
      i := !j
    end
    else if c = '\'' then begin
      if !i + 2 < n && s.[!i + 2] = '\'' then (push (Num (Char.code s.[!i + 1])); i := !i + 3)
      else if !i + 3 < n && s.[!i + 1] = '\\' && s.[!i + 3] = '\'' then begin
        let v = match s.[!i + 2] with
          | 'n' -> 10 | 'r' -> 13 | 't' -> 9 | '0' -> 0 | '\\' -> 92 | '\'' -> 39
          | x -> Loc.error loc "unknown escape '\\%c'" x in
        push (Num v); i := !i + 4
      end
      else Loc.error loc "malformed character literal"
    end
    else if c = '"' then begin
      let b = Buffer.create 16 in
      let j = ref (!i + 1) in
      while !j < n && s.[!j] <> '"' do
        if s.[!j] = '\\' && !j + 1 < n then begin
          (match s.[!j + 1] with
           | 'n' -> Buffer.add_char b '\n' | 't' -> Buffer.add_char b '\t'
           | x -> Buffer.add_char b x);
          j := !j + 2
        end
        else (Buffer.add_char b s.[!j]; incr j)
      done;
      if !j >= n then Loc.error loc "unterminated string";
      push (Str (Buffer.contents b));
      i := !j + 1
    end
    else if !i + 1 < n && List.mem (String.sub s !i 2) two_char_ops then begin
      push (Op (String.sub s !i 2));
      i := !i + 2
    end
    else if c = '.' then (push (Ident "."); incr i)
    else if String.contains one_char_ops c then (push (Op (String.make 1 c)); incr i)
    else if c = '\\' then Loc.error loc "'\\' outside a macro or .rep body (unknown parameter?)"
    else Loc.error loc "unexpected character %C" c
  done;
  List.rev !out
