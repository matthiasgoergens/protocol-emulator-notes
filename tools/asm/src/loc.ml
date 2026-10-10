(* Source locations and the one error type of the toolchain. Every message names the file and
   line, and, for a line that came out of a macro or a .rep block, where that was expanded. *)

type t = {
  file : string;
  line : int;
  chain : (string * string * int) list;   (* (what, file, line) of each expansion, innermost first *)
}

let none = { file = "<none>"; line = 0; chain = [] }

let to_string l =
  Printf.sprintf "%s:%d" l.file l.line
  ^ String.concat ""
      (List.map (fun (what, f, n) -> Printf.sprintf " (in %s at %s:%d)" what f n) l.chain)

exception Error of t * string

let error loc fmt = Printf.ksprintf (fun s -> raise (Error (loc, s))) fmt

let message loc msg = Printf.sprintf "%s: error: %s" (to_string loc) msg

(* warnings are collected, printed by the command line *)
let warnings : (t * string) list ref = ref []
let warn loc fmt = Printf.ksprintf (fun s -> warnings := (loc, s) :: !warnings) fmt
