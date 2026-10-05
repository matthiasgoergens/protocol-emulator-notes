(* Incremental bounded model checking in the style of Gergo Erdi's ScottCheck
   (github.com/gergoerdi/scottcheck, MIT; "ScottCheck: An Adventure in Symbolic Execution",
   IFL 2020): unroll the transition relation one step at a time in a single solver session, and
   after each step ask, inside a push/pop scope, whether the goal (here: a property violation)
   is reachable at exactly this depth. The unrolled steps stay asserted between depths, so the
   solver keeps what it learnt; only the goal is retracted. ScottCheck searches for a winning
   input sequence of a text adventure; here the "win" is a counterexample.

   Two shortcuts on top of the pattern: a goal that folded to the constant false while it was
   built is not sent to the solver at all (counted as "folded"), and environment assumptions are
   asserted at the top level as they appear, so they hold at every later depth. *)

type result = {
  name : string;
  depth : int;                       (* clocks unrolled *)
  violation : (int * Machine.model) option;   (* first failing clock and the model *)
  checks : int;                      (* check-sat calls on goals *)
  folded : int;                      (* depths whose goal folded to false *)
  solver_s : float;                  (* time inside check-sat *)
  total_s : float;
  defs : int;                        (* define-funs sent *)
  covers : (string * cover) list;    (* non-vacuity: each must be reachable *)
}

(* How a cover was decided. [Witnessed]: satisfiable with every variable fixed to a concrete
   witness (an input sequence found by running Isa2.Spec), so the solver only evaluates; a
   satisfying assignment is all that reachability needs. [Witness_failed]: the witness does not
   satisfy the cover (it says nothing about reachability; nothing else is tried). *)
and cover = Reachable | Unreachable | Witnessed of float | Witness_failed

let now () = Unix.gettimeofday ()

let log_dir () = match Sys.getenv_opt "BMC_SMT_LOG" with Some d -> Some d | None -> None

(* [step k] performs clock k and returns the clock's violation term and new assumptions;
   [covers ()], called after the last clock, returns named terms that must each be satisfiable
   (they are ghost flags meaning "this outcome has happened by now"). *)
(* [witnesses]: for some covers, by name, values for variables by their names: the inputs and the
   unconstrained instruction words. A variable the witness gives no value (None) is left free, as
   are bank (array) variables; the cut variables (Machine.cut) are fixed by their equations. *)
let run ?(progress = 0) ?(witnesses = []) ~name ~depth ~(step : int -> Smt.term * Smt.term list) ~(covers : unit -> (string * Smt.term) list) () =
  let log = Option.map (fun d -> Filename.concat d (name ^ ".smt2")) (log_dir ()) in
  let s = Smt.Solver.start ?log () in
  let t0 = now () in
  let solver_s = ref 0.0 and checks = ref 0 and folded = ref 0 in
  let check () = let t = now () in let r = Smt.Solver.check s in solver_s := !solver_s +. (now () -. t); r in
  let violation = ref None and k = ref 0 in
  while !violation = None && !k < depth do
    let bad, assumptions = step !k in
    List.iter (Smt.Solver.assert_ s) assumptions;
    (match Smt.bval bad with
     | Some false -> incr folded
     | _ ->
       incr checks;
       Smt.Solver.ensure s bad;
       Smt.Solver.push s;
       Smt.Solver.assert_ s bad;
       (match check () with
        | `Unsat -> ()
        | `Sat -> violation := Some (!k, Machine.model_of (Smt.Solver.get_values s s.Smt.Solver.vars))
        | `Unknown r -> failwith ("solver: " ^ r));
       Smt.Solver.pop s);
    incr k;
    if progress > 0 && !k mod progress = 0 then
      Printf.printf "  %s depth %4d: %7d definitions, %4d goals checked, solver %7.2f s, total %7.2f s\n%!"
        name !k s.Smt.Solver.defs !checks !solver_s (now () -. t0);
    if Sys.getenv_opt "BMC_DEBUG" <> None then Printf.eprintf "  [%d term nodes built]\n%!" (Smt.nodes_built ())
  done;
  let covers =
    if !violation <> None then []
    else List.map (fun (cname, term) ->
        Smt.Solver.ensure s term;
        let witness = List.assoc_opt cname witnesses in
        let fixed = match witness with
          | None -> []
          | Some (w : string -> int option) ->
            List.filter_map (fun (v : Smt.term) ->
                match v.node, v.sort with
                | Var n, Smt.Bool -> Option.map (fun x -> if x = 1 then v else Smt.not_ v) (w n)
                | Var n, Smt.Bv width -> Option.map (fun x -> Smt.eq v (Smt.k ~w:width x)) (w n)
                | _ -> None) s.Smt.Solver.vars in
        (* definitions outside the push, which would otherwise discard them *)
        List.iter (Smt.Solver.ensure s) fixed;
        Smt.Solver.push s; Smt.Solver.assert_ s term;
        List.iter (Smt.Solver.assert_ s) fixed;
        let t = now () in
        let r = check () in
        Smt.Solver.pop s;
        (cname, match witness, r with
         | Some _, `Sat -> Witnessed (now () -. t)
         | Some _, `Unsat -> Witness_failed
         | Some _, `Unknown e -> failwith ("solver: " ^ e)
         | None, `Sat -> Reachable
         | None, `Unsat -> Unreachable
         | None, `Unknown e -> failwith ("solver: " ^ e))) (covers ()) in
  let defs = s.Smt.Solver.defs in
  Smt.Solver.close s;
  { name; depth = !k; violation = !violation; checks = !checks; folded = !folded; solver_s = !solver_s;
    total_s = now () -. t0; defs; covers }

let report r =
  Printf.printf "%s: %s; %d clocks unrolled, %d goals sent to the solver, %d folded to false, %d definitions; solver %.2f s, total %.2f s\n%!"
    r.name
    (match r.violation with
     | Some (k, _) -> Printf.sprintf "VIOLATED at clock %d" k
     | None -> "no violation")
    r.depth r.checks r.folded r.defs r.solver_s r.total_s;
  List.iter (fun (n, c) -> Printf.printf "  cover %-50s %s\n" n (match c with
      | Reachable -> "reachable"
      | Witnessed t -> Printf.sprintf "reachable (concrete witness, checked by the solver in %.2f s)" t
      | Witness_failed -> "WITNESS FAILED (reachability not decided)"
      | Unreachable -> "NOT REACHABLE (vacuous?)")) r.covers
