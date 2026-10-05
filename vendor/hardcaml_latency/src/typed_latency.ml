open Hardcaml

type z
type !'n s
type 'n t = Signal.t

let to_signal t = t
let input = Signal.input
let of_int = Signal.of_int
let unsafe_of_signal t = t
let ( &: ) = Signal.( &: )
let ( |: ) = Signal.( |: )
let ( ^: ) = Signal.( ^: )
let ( ~: ) = Signal.( ~: )
let ( +: ) = Signal.( +: )
let ( ==: ) = Signal.( ==: )
let ( <: ) = Signal.( <: )
let mux2 = Signal.mux2
let mux = Signal.mux
let select = Signal.select
let reg spec t = Signal.reg spec t

type ('a, 'b) delay =
  | Z : ('a, 'a) delay
  | S : ('a, 'b) delay -> ('a, 'b s) delay

let rec cycles : type a b. (a, b) delay -> int = function
  | Z -> 0
  | S d -> 1 + cycles d
;;

let delay spec d t = Signal.pipeline spec ~n:(cycles d) t
