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

(* An SRAM macro (macros.ml has the model and its source): the pins as
   signals, LSB first, and the contents. *)
type mem = {
  mowner : string;
  mspec : Macros.spec;
  mclk : int; men : int; wen : int; ren : int; bist_en : int;
  addr : int array; din : int array; bm : int array; dout : int array;
  data : int array;
  mutable writes : int; mutable reads : int; mutable bist_edges : int;
}

type t = {
  gates : gate array;           (* topological order *)
  ffs : ff array;
  mems : mem array;
  v : int array;
  port : (string, int) Hashtbl.t;  (* port name -> signal *)
  const1 : int;                    (* the signal for 1'b1 *)
  (* which clock edge each flip-flop and macro takes: false = rising (the
     default, and what [cycle] does for all), true = falling; set by
     [classify_clocks] *)
  ff_fall : bool array;
  mem_fall : bool array;
}

let create (lib : (string, Cells.cell) Hashtbl.t) (nl : Extract.netlist) : t =
  (* two constant signals for the 1'b0 and 1'b1 in tie cells *)
  let const0 = nl.nnets and const1 = nl.nnets + 1 in
  let next = ref (nl.nnets + 2) in
  let fresh () = let s = !next in incr next; s in
  let gates = ref [] and ffs = ref [] and mems = ref [] in
  Array.iter (fun (inst : Extract.inst) ->
    match Hashtbl.find_opt lib inst.icell with
    | Some cell when Macros.is_macro inst.icell ->
      (match cell.unsupported, Macros.spec_of_name inst.icell with
       | None, Some sp ->
         let pin p = match List.assoc_opt p inst.nets with Some (Some n) -> n | _ -> fresh () in
         let bus p w = Array.init w (fun i -> pin (Printf.sprintf "%s[%d]" p i)) in
         mems := { mowner = inst.iname ^ "/" ^ inst.icell; mspec = sp;
                   mclk = pin "A_CLK"; men = pin "A_MEN"; wen = pin "A_WEN"; ren = pin "A_REN";
                   bist_en = pin "A_BIST_EN";
                   addr = bus "A_ADDR" sp.abits; din = bus "A_DIN" sp.width; bm = bus "A_BM" sp.width;
                   dout = bus "A_DOUT" sp.width; data = Array.make sp.words 0;
                   writes = 0; reads = 0; bist_edges = 0 } :: !mems
       | Some why, _ -> failwith (Printf.sprintf "%s: cannot simulate (%s)" inst.icell why)
       | None, None -> failwith (inst.icell ^ ": no memory model"))
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
  let ffs = Array.of_list (List.rev !ffs) and mems = Array.of_list (List.rev !mems) in
  { gates = Array.of_list (List.rev_map (fun i -> gates.(i)) !order);
    ffs; mems;
    v = Array.init nsig (fun i -> if i = const1 then 1 else 0); port; const1;
    ff_fall = Array.make (Array.length ffs) false; mem_fall = Array.make (Array.length mems) false }

(* Which edge of the clock port each flip-flop and macro takes, traced over
   the flattened gates: back from its clock pin through Buf and Not only, to
   the port, counting inversions.  Returns the counts (rising, falling) and
   the elements whose clock does not trace back that way; the edges are
   stored for [edge]. *)
let classify_clocks t ~clock =
  let port = match Hashtbl.find_opt t.port clock with Some s -> s | None -> failwith ("no clock port " ^ clock) in
  let driver = Hashtbl.create 4096 in
  Array.iter (fun g -> Hashtbl.replace driver g.out g) t.gates;
  let rec trace s inv depth =
    if s = port then Ok (inv mod 2 = 1)
    else if depth > 64 then Error "longer than 64 gates"
    else match Hashtbl.find_opt driver s with
      | Some { prim = Cells.Buf; ins; _ } -> trace ins.(0) inv (depth + 1)
      | Some { prim = Cells.Not; ins; _ } -> trace ins.(0) (inv + 1) (depth + 1)
      | Some _ -> Error "passes through a gate other than a buffer or inverter"
      | None -> Error "does not reach the clock port" in
  let rise = ref 0 and fall = ref 0 and bad = ref [] in
  let classify owner clk set =
    match trace clk 0 0 with
    | Ok f -> set f; if f then incr fall else incr rise
    | Error e -> bad := (owner ^ ": clock " ^ e) :: !bad in
  Array.iteri (fun i f -> classify f.owner f.clk (fun x -> t.ff_fall.(i) <- x)) t.ffs;
  Array.iteri (fun i m -> classify m.mowner m.mclk (fun x -> t.mem_fall.(i) <- x)) t.mems;
  (!rise, !fall, List.rev !bad)

(* every signal to 0 (flip-flops included), except the constant 1 *)
let reset t =
  Array.fill t.v 0 (Array.length t.v) 0;
  t.v.(t.const1) <- 1;
  Array.iter (fun m -> Array.fill m.data 0 (Array.length m.data) 0) t.mems

(* Evaluate every gate once, in order.  Written out per primitive, without
   allocating, because this loop is the whole cost of the lockstep run;
   Cells.eval_prim is the reference it must agree with (test_cells.ml). *)
let settle t =
  let v = t.v in
  let gates = t.gates in
  for gi = 0 to Array.length gates - 1 do
    let g = Array.unsafe_get gates gi in
    let ins = g.ins in
    let n = Array.length ins in
    (* no closures here: they were allocated per gate, which was most of the time *)
    let rec all x k = k >= n || (v.(ins.(k)) = x && all x (k + 1)) in
    let rec parity acc k = if k >= n then acc else parity (acc lxor v.(ins.(k))) (k + 1) in
    v.(g.out) <-
      (match g.prim with
       | Cells.And -> if all 1 0 then 1 else 0
       | Or -> if all 0 0 then 0 else 1
       | Nand -> if all 1 0 then 0 else 1
       | Nor -> if all 0 0 then 1 else 0
       | Xor -> parity 0 0
       | Xnor -> 1 - parity 0 0
       | Not -> 1 - v.(ins.(0))
       | Buf -> v.(ins.(0))
       | Mux2 -> if v.(ins.(2)) = 1 then v.(ins.(1)) else v.(ins.(0))
       | Mux4 -> v.(ins.(v.(ins.(5)) * 2 + v.(ins.(4)))))
  done

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

(* The macro's functional model on a clock edge (macros.ml): the inputs are
   sampled before any flip-flop or macro output changes; returns the new DOUT
   word, if it changes, for [commit_mem]. *)
let bits t a = Array.fold_left (fun (acc, k) s -> (acc lor (t.v.(s) lsl k), k + 1)) (0, 0) a |> fst

let sample_mem t m =
  if t.v.(m.bist_en) = 1 then (m.bist_edges <- m.bist_edges + 1; None)
  else if t.v.(m.men) = 0 then None
  else begin
    let a = bits t m.addr in
    if t.v.(m.wen) = 1 then begin
      let bm = bits t m.bm in
      let w = (m.data.(a) land lnot bm) lor (bits t m.din land bm) in
      m.data.(a) <- w;
      m.writes <- m.writes + 1;
      if t.v.(m.ren) = 1 then Some w else None
    end
    else if t.v.(m.ren) = 1 then (m.reads <- m.reads + 1; Some m.data.(a))
    else None
  end

let commit_mem t m = function
  | None -> ()
  | Some w -> Array.iteri (fun k s -> t.v.(s) <- (w lsr k) land 1) m.dout

(* One clock edge: every flip-flop and macro whose [*_fall] flag equals
   [fall] samples, then all of them update.  The memory writes happen in
   [sample_mem]; that is safe because nothing reads [data] but the macro
   itself, after every macro has sampled its inputs. *)
let edge t ~fall =
  settle t;
  apply_async t;
  let next = Array.mapi (fun i f -> if t.ff_fall.(i) = fall then t.v.(f.d) else t.v.(f.q)) t.ffs in
  let mnext = Array.mapi (fun i m -> if t.mem_fall.(i) = fall then sample_mem t m else None) t.mems in
  Array.iteri (fun i f -> t.v.(f.q) <- next.(i)) t.ffs;
  Array.iteri (fun i m -> commit_mem t m mnext.(i)) t.mems;
  settle t;
  apply_async t

(* inputs must be set before calling; outputs are read after it returns.
   Every flip-flop and macro takes this edge, whatever [classify_clocks]
   found (the single-clock blocks of the earlier round trips). *)
let cycle t =
  settle t;
  apply_async t;
  let next = Array.map (fun f -> t.v.(f.d)) t.ffs in
  let mnext = Array.map (sample_mem t) t.mems in
  Array.iteri (fun i f -> t.v.(f.q) <- next.(i)) t.ffs;
  Array.iteri (fun i m -> commit_mem t m mnext.(i)) t.mems;
  settle t;
  apply_async t
