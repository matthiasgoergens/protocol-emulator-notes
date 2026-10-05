(* Two-valued, cycle-based gate-level simulator for an extracted netlist.

   Same scheme as the puzzle solution's simulator (hardware-2026-08/oxcaml/
   sim.ml): every cell instance is flattened into its Verilog model's gate
   primitives over global signal ids, evaluated in one static topological
   order.  One clock: settle, sample every flip-flop's D, update every Q,
   settle.  Flip-flops are all clocked together; Check verifies separately
   that every clock pin is reached from the clock port through buffers and
   inverters only, which is what makes that sound for this design.

   Signals 0 .. nnets-1 are the extracted nets.  A net nobody drives keeps
   the value 0 for ever, and a pin with no metal under its label gets a fresh
   signal that also reads 0: exactly the behaviour that hid the puzzle chip's
   floating net from simulation, which is why Check reports both before any
   simulation is trusted. *)

type gate = { prim : Cells.prim; out : int; ins : int array }

type ff = { q : int; clk : int; d : int; r : int; s : int; owner : string }
(* r, s = -1 when absent *)

type t = {
  gates : gate array;           (* topological order *)
  ffs : ff array;
  v : int array;
  port : (string, int) Hashtbl.t;  (* port name -> signal *)
  const1 : int;                    (* the signal for 1'b1 *)
}

let create (lib : (string, Cells.cell) Hashtbl.t) (nl : Extract.netlist) : t =
  (* two constant signals for the 1'b0 and 1'b1 in tie cells *)
  let const0 = nl.nnets and const1 = nl.nnets + 1 in
  let next = ref (nl.nnets + 2) in
  let fresh () = let s = !next in incr next; s in
  let gates = ref [] and ffs = ref [] in
  Array.iter (fun (inst : Extract.inst) ->
    match Hashtbl.find_opt lib inst.icell with
    | None -> failwith ("no model for " ^ inst.icell)
    | Some cell ->
      (match cell.unsupported with
       | Some why -> failwith (Printf.sprintf "%s: cannot simulate (%s)" inst.icell why)
       | None -> ());
      let local = Hashtbl.create 8 in
      List.iter (fun (p, n) ->
        Hashtbl.replace local p (match n with Some n -> n | None -> fresh ())) inst.nets;
      let sig_of w =
        if w = "1'b0" then const0 else if w = "1'b1" then const1 else
        match Hashtbl.find_opt local w with
        | Some s -> s
        | None -> let s = fresh () in Hashtbl.replace local w s; s
      in
      Array.iter (fun (g : Cells.gate) ->
        gates := { prim = g.gprim; out = sig_of g.gout; ins = Array.map sig_of g.gins } :: !gates)
        cell.gates;
      List.iter (fun (f : Cells.ff) ->
        let opt = function None -> -1 | Some w -> sig_of w in
        ffs := { q = sig_of f.q; clk = sig_of f.clk; d = sig_of f.d; r = opt f.r; s = opt f.s;
                 owner = inst.iname ^ "/" ^ inst.icell } :: !ffs)
        cell.ffs)
    nl.instances;
  let nsig = !next in
  let gates = Array.of_list (List.rev !gates) in
  (* Kahn's algorithm over signals driven by gates *)
  let driver = Array.make nsig (-1) in
  Array.iteri (fun i g -> driver.(g.out) <- i) gates;
  let pending = Array.map (fun g ->
      Array.fold_left (fun acc s -> if driver.(s) >= 0 then acc + 1 else acc) 0 g.ins) gates in
  let users = Array.make nsig [] in
  Array.iteri (fun i g -> Array.iter (fun s -> if driver.(s) >= 0 then users.(s) <- i :: users.(s)) g.ins) gates;
  let queue = Queue.create () in
  Array.iteri (fun i c -> if c = 0 then Queue.add i queue) pending;
  let order = ref [] in
  while not (Queue.is_empty queue) do
    let i = Queue.pop queue in
    order := i :: !order;
    (* every gate driving this signal counts once per input occurrence *)
    List.iter (fun u -> pending.(u) <- pending.(u) - 1; if pending.(u) = 0 then Queue.add u queue)
      users.(gates.(i).out)
  done;
  if List.length !order <> Array.length gates then
    failwith (Printf.sprintf "combinational loop: %d of %d gates unordered"
                (Array.length gates - List.length !order) (Array.length gates));
  let port = Hashtbl.create 64 in
  List.iter (fun (p, n) -> Option.iter (fun n -> Hashtbl.replace port p n) n) nl.ports;
  { gates = Array.of_list (List.rev_map (fun i -> gates.(i)) !order);
    ffs = Array.of_list (List.rev !ffs);
    v = Array.init nsig (fun i -> if i = const1 then 1 else 0); port; const1 }

(* every signal to 0 (flip-flops included), except the constant 1 *)
let reset t =
  Array.fill t.v 0 (Array.length t.v) 0;
  t.v.(t.const1) <- 1

(* Evaluate every gate once, in order.  Written out per primitive, without
   allocating, because this loop is the whole cost of the lockstep run;
   Cells.eval_prim is the reference it must agree with (test_cells.ml). *)
let settle t =
  let v = t.v in
  Array.iter (fun g ->
    let ins = g.ins in
    let n = Array.length ins in
    let all x = let r = ref true in for k = 0 to n - 1 do if v.(ins.(k)) <> x then r := false done; !r in
    let parity () = let r = ref 0 in for k = 0 to n - 1 do r := !r lxor v.(ins.(k)) done; !r in
    v.(g.out) <-
      (match g.prim with
       | Cells.And -> if all 1 then 1 else 0
       | Or -> if all 0 then 0 else 1
       | Nand -> if all 1 then 0 else 1
       | Nor -> if all 0 then 1 else 0
       | Xor -> parity ()
       | Xnor -> 1 - parity ()
       | Not -> 1 - v.(ins.(0))
       | Buf -> v.(ins.(0))
       | Mux2 -> if v.(ins.(2)) = 1 then v.(ins.(1)) else v.(ins.(0))
       | Mux4 -> v.(ins.(v.(ins.(5)) * 2 + v.(ins.(4))))))
    t.gates

(* asynchronous set and reset, then settle again until nothing changes *)
let apply_async t =
  let changed = ref true and rounds = ref 0 in
  while !changed do
    changed := false;
    incr rounds;
    if !rounds > 10 then failwith "asynchronous set/reset does not settle";
    Array.iter (fun f ->
      let forced =
        if f.r >= 0 && t.v.(f.r) = 1 then Some 0
        else if f.s >= 0 && t.v.(f.s) = 1 then Some 1 else None in
      match forced with
      | Some x when t.v.(f.q) <> x -> t.v.(f.q) <- x; changed := true
      | _ -> ()) t.ffs;
    if !changed then settle t
  done

let set_input t name value =
  match Hashtbl.find_opt t.port name with
  | Some s -> t.v.(s) <- value
  | None -> failwith ("no port " ^ name)

let get t name =
  match Hashtbl.find_opt t.port name with
  | Some s -> t.v.(s)
  | None -> failwith ("no port " ^ name)

(* inputs must be set before calling; outputs are read after it returns *)
let cycle t =
  settle t;
  apply_async t;
  let next = Array.map (fun f -> t.v.(f.d)) t.ffs in
  Array.iteri (fun i f -> t.v.(f.q) <- next.(i)) t.ffs;
  settle t;
  apply_async t
