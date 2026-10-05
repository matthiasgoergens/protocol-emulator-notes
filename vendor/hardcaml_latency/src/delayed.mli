(** Signals that carry their pipeline latency, checked while the circuit is built.

    A [Delayed.t] is a [Signal.t] together with a latency: the number of register stages
    between it and the signals the design treats as time zero (usually the circuit
    inputs, or a free-running timing counter). Every combinational operator demands that
    its operands have the same latency and raises otherwise, naming the operation, each
    operand's latency and the source line that created it. A register adds one.

    This is the elaboration-time counterpart of Clash's [DSignal dom d a]: the check is
    not done by the OCaml type checker, but it still happens before any simulation, when
    the OCaml program that builds the circuit runs, and it handles arbitrary arithmetic
    on latencies.

    The whole of Hardcaml's combinational API ([Comb.S]) is available on [Delayed.t]
    because it is generated with [Comb.Make] from a handful of checked primitives.

    Constants have latency [Static], which is compatible with every latency. So are
    signals the designer declares quasi-static with [static] (configuration registers,
    per-line parameters), which is an escape hatch and the designer's responsibility.

    Register enables, clears and resets are plain [Signal.t]s and are not checked: as in
    Clash, where enables belong to the clock domain, a stall applies to every stage of a
    pipeline in the same cycle, so it has no single latency relative to the data. *)

open Hardcaml

module Latency : sig
  type t =
    | Static (** constant or declared quasi-static: compatible with any latency *)
    | At of int
  [@@deriving sexp_of, equal]

  val to_string : t -> string
end

(** Raised by every operation whose operands disagree on latency. The string is the
    complete, human-readable message. *)
exception Latency_mismatch of string

include Comb.S

val latency : t -> Latency.t

(** [latency_exn t] is the latency of [t]; raises if [t] is [Static]. *)
val latency_exn : t -> int

val to_signal : t -> Signal.t

(** {2 Entering and leaving the latency discipline} *)

(** A circuit input at [latency] (default 0). *)
val input : ?latency:int -> string -> int -> t

(** A circuit output; the latency is dropped. *)
val output : string -> t -> Signal.t

(** Wrap an existing signal, asserting its latency. *)
val of_signal : latency:int -> Signal.t -> t

(** Declare a signal quasi-static: it changes rarely enough (once a line, once a frame)
    that combining it with any latency is intended. Not checked. *)
val static : Signal.t -> t

(** {2 Registers} *)

(** One register stage: latency + 1, except that a register of a [Static] signal stays
    [Static]. [enable] is a plain signal and is not checked. *)
val reg : Reg_spec.t -> ?enable:Signal.t -> t -> t

(** [n] register stages: latency + n. *)
val pipeline : Reg_spec.t -> ?enable:Signal.t -> n:int -> t -> t

(** Delay [t] until it reaches [latency]. Raises if [t] is already later. *)
val delay_to : Reg_spec.t -> ?enable:Signal.t -> latency:int -> t -> t

(** Delay every signal to the latest latency among them; [Static] signals are left
    alone. This is Erdi's [delayVGA] / Clash's [matchDelay] generalised to a list. *)
val align : Reg_spec.t -> ?enable:Signal.t -> t list -> t list

(** State that feeds back on itself, such as a counter or a state machine, following
    Erdi's [delayedRegister]: [f] sees the current state at [latency] (Clash's
    [antiDelay]) and must return the next state at [latency] (or [Static]), so that it
    may combine the state with inputs at [latency]. The register's output is at
    [latency + 1], because it reflects those inputs one cycle later. *)
val reg_fb
  :  ?enable:Signal.t
  -> Reg_spec.t
  -> latency:int
  -> width:int
  -> f:(t -> t)
  -> t

(** Use an existing, unchecked Hardcaml circuit with a known latency, such as a pipelined
    multiplier from [Hardcaml_circuits]: the arguments must agree on latency [l], and the
    result is at [l + latency]. *)
val lift : name:string -> latency:int -> (Signal.t list -> Signal.t) -> t list -> t

(** {2 Interfaces} *)

module Of_interface (I : Interface.S) : sig
  val of_signals : latency:int -> Signal.t I.t -> t I.t
  val to_signals : t I.t -> Signal.t I.t

  (** The common latency of all fields. Raises, listing the fields, if they disagree. *)
  val latency_exn : t I.t -> Latency.t

  (** Delay every field to the latest field's latency. *)
  val align : Reg_spec.t -> ?enable:Signal.t -> t I.t -> t I.t

  val reg : Reg_spec.t -> ?enable:Signal.t -> t I.t -> t I.t
  val pipeline : Reg_spec.t -> ?enable:Signal.t -> n:int -> t I.t -> t I.t
end
