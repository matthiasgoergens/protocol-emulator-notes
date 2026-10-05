(** Latency in the OCaml type, checked by the compiler: a sketch of design (a).

    ['n t] is a signal at latency ['n], where ['n] is a type-level Peano number built
    from [z] and [_ s]. A register turns ['n t] into ['n s t]; every operator demands the
    same ['n] on all operands, so mixing a path delayed by three with one delayed by two
    is a compile-time type error.

    OCaml has no type-level arithmetic, so "delay by k" cannot be a function of an
    integer. Instead a delay is a singleton GADT witness [('a, 'b) delay] that proves
    ['b = 'a + k] by construction: [S (S Z)] has type [('a, 'a s s) delay] for every
    ['a]. Functions can be latency-polymorphic ([val f : 'n t -> 'n s s t]), which is the
    useful part. What cannot be written is anything whose latency depends on a run-time
    value ([pipeline ~n] for a computed [n]) or an [align] that works out by itself which
    of two signals is later: the caller has to write the witness, and the compiler
    checks it.

    Only a handful of operators are provided: Hardcaml's [Comb.Make] needs a monomorphic
    [t] and cannot generate the API for a parameterised ['n t], so each of the ~200
    operators would have to be wrapped by hand or by code generation. *)

open Hardcaml

type z
type !'n s
type 'n t

val to_signal : 'n t -> Signal.t

(** Circuit inputs are at latency zero. *)
val input : string -> int -> z t

(** Constants are latency-polymorphic. *)
val of_int : width:int -> int -> 'n t

(** Escape hatch: assert the latency of an existing signal. Unchecked. *)
val unsafe_of_signal : Signal.t -> 'n t

val ( &: ) : 'n t -> 'n t -> 'n t
val ( |: ) : 'n t -> 'n t -> 'n t
val ( ^: ) : 'n t -> 'n t -> 'n t
val ( ~: ) : 'n t -> 'n t
val ( +: ) : 'n t -> 'n t -> 'n t
val ( ==: ) : 'n t -> 'n t -> 'n t
val ( <: ) : 'n t -> 'n t -> 'n t
val mux2 : 'n t -> 'n t -> 'n t -> 'n t
val mux : 'n t -> 'n t list -> 'n t
val select : 'n t -> int -> int -> 'n t
val reg : Reg_spec.t -> 'n t -> 'n s t

(** [('a, 'b) delay] witnesses ['b = 'a + k]. *)
type ('a, 'b) delay =
  | Z : ('a, 'a) delay
  | S : ('a, 'b) delay -> ('a, 'b s) delay

val delay : Reg_spec.t -> ('a, 'b) delay -> 'a t -> 'b t
val cycles : ('a, 'b) delay -> int
