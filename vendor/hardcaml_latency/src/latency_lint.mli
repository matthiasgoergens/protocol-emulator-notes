(** A lint over a finished Hardcaml circuit: find places where two paths from a common
    source meet after passing through different numbers of registers.

    Every node gets a latency label such that for each data edge [u -> v],
    [latency v = latency u + 1] if [v] is a register fed by [u] and [latency u] otherwise.
    These are equality constraints, solved with a union-find that carries offsets. A
    constraint that contradicts the ones already known is a finding: a reconvergence point
    whose inputs are a different number of cycles behind a common source.

    What is not a data edge:
    - clocks, asynchronous resets and synchronous clears;
    - register enables, unless [check_enables] (a stall applies to every stage in the same
      cycle, so it has no single latency relative to the data);
    - memories and instantiations: their outputs start new, unconstrained components;
    - the edges that close a feedback loop: an input to a register that comes from the
      register's own strongly connected component. A register in a loop takes the latency
      of the inputs entering the loop (not one more), as Clash's [feedback] does, so that
      a state machine may combine its state with its inputs.

    Constants are compatible with everything, as are signals that [static] accepts and,
    with [hold_registers], every register with a non-constant enable (on the theory that it
    holds a configuration value for many cycles). *)

open Hardcaml

type finding =
  { at : string (** the reconvergence point *)
  ; anchor : string (** what the latencies are measured from *)
  ; expected : string * int (** an input of [at] and its latency after [anchor] *)
  ; got : string * int (** another input that disagrees *)
  }

type result =
  { findings : finding list
  ; nodes : int (** nodes in the graph *)
  ; checked : int (** nodes not static, i.e. carrying a latency *)
  ; loop_registers : int (** registers in feedback loops (feedback edges are cut) *)
  ; cut_boundaries : int (** memories and instantiations, across which nothing is tracked *)
  }

val check
  :  ?check_enables:bool (** default [false] *)
  -> ?hold_registers:bool (** default [false] *)
  -> ?static:(Signal.t -> bool) (** default: nothing *)
  -> Signal.t list
  -> result

val check_circuit
  :  ?check_enables:bool
  -> ?hold_registers:bool
  -> ?static:(Signal.t -> bool)
  -> Circuit.t
  -> result

val to_string : finding -> string

(** Print the findings with a header saying how much of the circuit was checked, and a
    warning if nothing was. *)
val report : title:string -> result -> unit
