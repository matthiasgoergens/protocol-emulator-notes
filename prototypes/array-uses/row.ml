(* A segment of upe_v0 PEs in a chain, wired as notes/architecture-v0.md section 2.4 describes:
   A (and its valid bit) from the left neighbour's P, the lane from the left neighbour's lane out
   (or the segment's broadcast bit), pair wires s15 and g from the left, the carry-back bit from
   the right neighbour's S[15], and the configuration chain from PE 0 to the last PE. PE 0 takes
   the segment feed. Per clock the combinational outputs are evaluated left to right (g and the
   lane may ripple), then every PE is clocked. *)

type t = { pes : Upe.state array; mutable outs : Upe.outputs array }

let create n = { pes = Array.init n (fun _ -> Upe.create ()); outs = [||] }

let dummy : Upe.outputs = { cfg_out = 0; init_out = 0; p_out = 0; p_valid = 0; b_out = 0; cb_out = 0; s15_out = 0; g_out = 0; flag = 0; s_out = 0 }

type seg_in = {
  feed : int; feed_valid : int; bcast : int; en : int; clear : int;
  cfg_in : int; cfg_strobe : int;
}

let seg_idle = { feed = 0; feed_valid = 1; bcast = 0; en = 1; clear = 0; cfg_in = 0; cfg_strobe = 0 }

(* evaluates the clock and returns the last PE's outputs of this cycle (before the edge) *)
let step r (si : seg_in) =
  let n = Array.length r.pes in
  let ins = Array.make n Upe.idle in
  let outs = Array.make n dummy in
  for i = 0 to n - 1 do
    let left = if i = 0 then None else Some outs.(i - 1) in
    let cb_in = if i = n - 1 then 0 else Upe.bit r.pes.(i + 1).Upe.s 15 in
    let cfg_in = match left with None -> si.cfg_in | Some _ -> r.pes.(i - 1).Upe.c.(7) in
    let i_ : Upe.inputs = {
      clear = si.clear; cfg_in; cfg_strobe = si.cfg_strobe; init_in = 0; init_strobe = 0;
      en = si.en;
      a = (match left with None -> si.feed | Some o -> o.p_out);
      a_valid = (match left with None -> si.feed_valid | Some o -> o.p_valid);
      b_in = (match left with None -> 0 | Some o -> o.b_out);
      bc_in = si.bcast; cb_in;
      s15_in = (match left with None -> 0 | Some o -> o.s15_out);
      g_in = (match left with None -> 0 | Some o -> o.g_out) } in
    ins.(i) <- i_;
    outs.(i) <- Upe.outputs r.pes.(i) i_
  done;
  r.outs <- outs;
  (* clock: all PEs see the values sampled above; the chain shifts from the pre-edge c.(7) *)
  Array.iteri (fun i pe -> Upe.clock pe ins.(i)) r.pes;
  outs.(n - 1)

(* configuration bytes for the whole segment: the last PE's bytes go in first *)
let chain_bytes (cfgs : int list array) =
  List.concat (List.rev (Array.to_list cfgs))

let load_direct r (cfgs : int list array) = Array.iteri (fun i b -> Upe.load r.pes.(i) b) cfgs
