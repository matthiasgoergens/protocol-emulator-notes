open Base
open Hardcaml

module Latency = struct
  type t =
    | Static
    | At of int
  [@@deriving sexp_of, equal]

  let to_string = function
    | Static -> "static"
    | At n -> Int.to_string n
  ;;
end

exception Latency_mismatch of string

let () =
  Stdlib.Printexc.register_printer (function
    | Latency_mismatch msg -> Some msg
    | _ -> None)
;;

(* The first stack frame outside this library and Hardcaml itself, i.e. the line of the
   user's design that built the signal. Both libraries keep their sources under [src/],
   so frames there are skipped. Needs the program to be built with [-g] (dune's default). *)
let call_site () =
  let open Stdlib.Printexc in
  match backtrace_slots (get_callstack 40) with
  | None -> None
  | Some slots ->
    Array.find_map slots ~f:(fun slot ->
      match Slot.location slot with
      | Some { filename; line_number; _ }
        when not (String.is_prefix filename ~prefix:"src/") ->
        Some (Printf.sprintf "%s:%d" filename line_number)
      | _ -> None)
;;

module Primitives = struct
  type t =
    { signal : Signal.t
    ; latency : Latency.t
    ; site : string option
    }

  let sexp_of_t t =
    [%sexp
      { signal = (t.signal : Signal.t)
      ; latency = (t.latency : Latency.t)
      ; site = (t.site : string option)
      }]
  ;;

  let equal a b = Signal.equal a.signal b.signal && Latency.equal a.latency b.latency
  let make signal latency = { signal; latency; site = call_site () }
  let static_ signal = { signal; latency = Static; site = None }

  let describe t =
    let name =
      match Signal.names t.signal with
      | [] -> None
      | names -> Some (String.concat ~sep:"/" names)
    in
    match List.filter_opt [ name; t.site ] with
    | [] -> ""
    | parts -> Printf.sprintf "  (%s)" (String.concat ~sep:", " parts)
  ;;

  (* The common latency of [operands], raising if two non-static ones differ. *)
  let check ~op (operands : (string * t) list) =
    let latencies =
      List.filter_map operands ~f:(fun (_, t) ->
        match t.latency with
        | Static -> None
        | At n -> Some n)
      |> List.dedup_and_sort ~compare:Int.compare
    in
    match latencies with
    | [] -> Latency.Static
    | [ n ] -> At n
    | _ ->
      let site =
        match call_site () with
        | Some s -> " at " ^ s
        | None -> ""
      in
      let max = List.last_exn latencies in
      let lines =
        List.map operands ~f:(fun (label, t) ->
          Printf.sprintf
            "    %-8s latency %-6s%s"
            label
            (Latency.to_string t.latency)
            (describe t))
      in
      let fix =
        List.filter_map operands ~f:(fun (label, t) ->
          match t.latency with
          | At n when n < max ->
            Some (Printf.sprintf "%s needs %d more register stage(s)" label (max - n))
          | _ -> None)
      in
      raise
        (Latency_mismatch
           (String.concat
              ~sep:"\n"
              ([ Printf.sprintf "Latency mismatch in [%s]%s:" op site ]
               @ lines
               @ [ Printf.sprintf
                     "  To line them up: %s (Delayed.pipeline / Delayed.align)."
                     (String.concat ~sep:"; " fix)
                 ])))
  ;;

  let op1 ~op f a = make (f a.signal) (check ~op [ "arg", a ])

  let op2 ~op f a b =
    let latency = check ~op [ "left", a; "right", b ] in
    make (f a.signal b.signal) latency
  ;;

  let empty = static_ Signal.empty
  let is_empty t = Signal.is_empty t.signal
  let width t = Signal.width t.signal
  let of_constant c = static_ (Signal.of_constant c)
  let to_constant t = Signal.to_constant t.signal
  let to_string t = Signal.to_string t.signal

  let concat_msb ts =
    let latency =
      check ~op:"concat" (List.mapi ts ~f:(fun i t -> Printf.sprintf "arg %d" i, t))
    in
    make (Signal.concat_msb (List.map ts ~f:(fun t -> t.signal))) latency
  ;;

  let select t hi lo = { t with signal = Signal.select t.signal hi lo }
  let ( -- ) t name = { t with signal = Signal.( -- ) t.signal name }
  let ( &: ) = op2 ~op:"&:" Signal.( &: )
  let ( |: ) = op2 ~op:"|:" Signal.( |: )
  let ( ^: ) = op2 ~op:"^:" Signal.( ^: )
  let ( ~: ) = op1 ~op:"~:" Signal.( ~: )
  let ( +: ) = op2 ~op:"+:" Signal.( +: )
  let ( -: ) = op2 ~op:"-:" Signal.( -: )
  let ( *: ) = op2 ~op:"*:" Signal.( *: )
  let ( *+ ) = op2 ~op:"*+" Signal.( *+ )
  let ( ==: ) = op2 ~op:"==:" Signal.( ==: )
  let ( <: ) = op2 ~op:"<:" Signal.( <: )

  let mux sel cases =
    let latency =
      check
        ~op:"mux"
        (("select", sel) :: List.mapi cases ~f:(fun i t -> Printf.sprintf "case %d" i, t))
    in
    make (Signal.mux sel.signal (List.map cases ~f:(fun t -> t.signal))) latency
  ;;
end

include Primitives
include Comb.Make (Primitives)

let latency t = t.latency

let latency_exn t =
  match t.latency with
  | At n -> n
  | Static -> raise_s [%message "Delayed.latency_exn: signal is static" (t : t)]
;;

let to_signal t = t.signal
let of_signal ~latency s = make s (At latency)
let input ?(latency = 0) name width = of_signal ~latency (Signal.input name width)
let output name t = Signal.output name t.signal
let static s = { signal = s; latency = Static; site = call_site () }

let shift latency n =
  match (latency : Latency.t) with
  | Static -> Latency.Static
  | At l -> At (l + n)
;;

let reg spec ?enable t = make (Signal.reg spec ?enable t.signal) (shift t.latency 1)

let pipeline spec ?enable ~n t =
  if n = 0 then t else make (Signal.pipeline spec ?enable ~n t.signal) (shift t.latency n)
;;

let delay_to spec ?enable ~latency t =
  match t.latency with
  | Static -> t
  | At l when l <= latency -> pipeline spec ?enable ~n:(latency - l) t
  | At l ->
    raise
      (Latency_mismatch
         (Printf.sprintf
            "Delayed.delay_to: signal %s is already at latency %d, later than the target %d"
            (String.strip (describe t))
            l
            latency))
;;

let latest ts =
    List.fold ts ~init:None ~f:(fun acc t ->
      match t.latency, acc with
      | Static, _ -> acc
      | At l, None -> Some l
      | At l, Some m -> Some (Int.max l m))
;;

let align spec ?enable ts =
  match latest ts with
  | None -> ts
  | Some latency -> List.map ts ~f:(delay_to spec ?enable ~latency)
;;

let reg_fb ?enable spec ~latency ~width ~f =
  let q =
    Signal.reg_fb spec ?enable ~width ~f:(fun q ->
      let next = f (of_signal ~latency q) in
      ignore (check ~op:"reg_fb next state" [ "state", of_signal ~latency q; "next", next ]
              : Latency.t);
      next.signal)
  in
  of_signal ~latency:(latency + 1) q
;;

let lift ~name ~latency f args =
  let l =
    check ~op:name (List.mapi args ~f:(fun i t -> Printf.sprintf "arg %d" i, t))
  in
  make (f (List.map args ~f:to_signal)) (shift l latency)
;;

module Of_interface (I : Interface.S) = struct
  let of_signals ~latency s = I.map s ~f:(of_signal ~latency)
  let to_signals t = I.map t ~f:to_signal

  let latency_exn t =
    check
      ~op:(Printf.sprintf "interface with fields %s"
             (String.concat ~sep:"," (I.to_list I.port_names)))
      (I.to_list (I.map2 I.port_names t ~f:(fun n t -> n, t)))
  ;;

  let align spec ?enable t =
    match latest (I.to_list t) with
    | None -> t
    | Some latency -> I.map t ~f:(delay_to spec ?enable ~latency)
  ;;

  let reg spec ?enable t = I.map t ~f:(reg spec ?enable)
  let pipeline spec ?enable ~n t = I.map t ~f:(pipeline spec ?enable ~n)
end
