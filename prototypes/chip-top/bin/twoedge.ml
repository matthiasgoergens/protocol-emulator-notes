(* The pieces shared by the gate-level lockstep (gate_lockstep.ml) and the edge-phase test
   (edge_phase.ml): the two-part Hardcaml reference clocked edge by edge (Ref2), Tt_top.create on
   one edge (Ref1), and the gates extracted from a GDS (Gates). See gate_lockstep.ml's header. *)

open Hardcaml

let n_pads = Regs.n_pads

(* ---- the reference ---- *)

module Ref2 = struct
  (* the two-part reference; [split]: phases 0-1 on the rising edge, 2-3 on the falling *)
  type t = {
    a : Cyclesim.t_port_list; b : Cyclesim.t_port_list;
    a_smp : Bits.t ref; a_rst : Bits.t ref; b_sub : Bits.t ref; b_clear : Bits.t ref;
    b_pads : Bits.t ref; b_en : Bits.t ref;
    a_folded_before : Bits.t ref; a_reset_before : Bits.t ref;
    a_folded : Bits.t ref; a_reset : Bits.t ref; a_oe : Bits.t ref;
    b_pins : Bits.t ref; b_samples : Bits.t ref;
  }

  let core_circuit cfg =
    let open Signal in
    let clk = input "clk" 1 and rst_n = input "rst_n" 1 and smp = input "smp" (4 * n_pads) in
    let reset = Tt_top.reset_sync ~clk ~rst_n in
    let folded, oe = Tt_top.core_side ~cfg ~memories:`Behavioural ~clk ~reset ~smp () in
    Circuit.create_exn ~name:"core_side" [ output "folded" folded; output "uio_oe" oe; output "reset" reset ]

  let create cfg =
    let a = Cyclesim.create (core_circuit cfg) in
    let b = Cyclesim.create (Mphase.Stage.circuit_substep ~n_out:n_pads ~n_in:n_pads ()) in
    let ia = Cyclesim.in_port a and ib = Cyclesim.in_port b in
    let oa ?clock_edge n = Cyclesim.out_port ?clock_edge a n and ob n = Cyclesim.out_port b n in
    { a; b; a_smp = ia "smp"; a_rst = ia "rst_n"; b_sub = ib "sub"; b_clear = ib "clear";
      b_pads = ib "pads"; b_en = ib "en";
      a_folded_before = oa ~clock_edge:Before "folded"; a_reset_before = oa ~clock_edge:Before "reset";
      a_folded = oa "folded"; a_reset = oa "reset"; a_oe = oa "uio_oe";
      b_pins = ob "pin"; b_samples = ob "samples" }

  (* the rising edge: every register of the core side, and the stage's phases [en] *)
  let rise t ~rst_n ~pads ~en =
    t.a_smp := !(t.b_samples);   (* register outputs of the stage: their value before the edge *)
    t.a_rst := Bits.of_int ~width:1 rst_n;
    Cyclesim.cycle_check t.a;
    Cyclesim.cycle_before_clock_edge t.a;
    t.b_sub := !(t.a_folded_before);
    t.b_clear := !(t.a_reset_before);
    t.b_pads := Bits.of_int ~width:n_pads pads;
    t.b_en := Bits.of_int ~width:4 en;
    Cyclesim.cycle_check t.b;
    Cyclesim.cycle_before_clock_edge t.b;
    Cyclesim.cycle_at_clock_edge t.a;
    Cyclesim.cycle_after_clock_edge t.a;
    Cyclesim.cycle_at_clock_edge t.b;
    Cyclesim.cycle_after_clock_edge t.b

  (* the falling edge: the stage's phases 2 and 3, from the core side's values after the rise *)
  let fall t ~pads =
    t.b_sub := !(t.a_folded);
    t.b_clear := !(t.a_reset);
    t.b_pads := Bits.of_int ~width:n_pads pads;
    t.b_en := Bits.of_int ~width:4 0b1100;
    Cyclesim.cycle t.b

  (* uo_out | uio_out << 8 | uio_oe << 16 *)
  let outputs t = Bits.to_int !(t.b_pins) lor (Bits.to_int !(t.a_oe) lsl 16)
end

module Ref1 = struct
  (* Tt_top.create itself, every register on one edge *)
  type t = { sim : Cyclesim.t_port_list; ui : Bits.t ref; uio : Bits.t ref; rst : Bits.t ref;
             uo : Bits.t ref; uio_out : Bits.t ref; oe : Bits.t ref }

  let create cfg =
    let sim = Cyclesim.create (Tt_top.create ~cfg ~memories:`Behavioural ~name:"chip_tt" ()) in
    let i = Cyclesim.in_port sim and o n = Cyclesim.out_port sim n in
    { sim; ui = i "ui_in"; uio = i "uio_in"; rst = i "rst_n"; uo = o "uo_out"; uio_out = o "uio_out"; oe = o "uio_oe" }

  let cycle t ~rst_n ~pads =
    t.ui := Bits.of_int ~width:8 (pads land 0xFF);
    t.uio := Bits.of_int ~width:8 (pads lsr 8);
    t.rst := Bits.of_int ~width:1 rst_n;
    Cyclesim.cycle t.sim

  let outputs t = Bits.to_int !(t.uo) lor (Bits.to_int !(t.uio_out) lsl 8) lor (Bits.to_int !(t.oe) lsl 16)
end

(* ---- the gates ---- *)

module Gates = struct
  type t = { sim : Sim.t; ins : int array; rst : int; outs : int array }

  let create ~gds ~models =
    let lib = Cells.parse_library models in
    let nl, _ = Extract.extract ~gds_path:gds ~top_name:"tt_um_chip_top" () in
    Macros.add_to_lib ~models lib nl;
    let ports = [ "clk"; "rst_n"; "ena" ] @ List.init 8 (Printf.sprintf "ui_in[%d]") @ List.init 8 (Printf.sprintf "uio_in[%d]") in
    let rtl_ports =
      List.map (fun p -> (p, Check.In)) ports
      @ List.concat_map (fun b -> List.init 8 (fun i -> (Printf.sprintf "%s[%d]" b i, Check.Out))) [ "uo_out"; "uio_out"; "uio_oe" ] in
    let report = Check.run ~falling_ok:true ~lib ~ports:rtl_ports ~clock:"clk" nl in
    Printf.printf "gates: %d instances, %d nets; structural check: %d errors\n%!" (Array.length nl.instances) nl.nnets
      (List.length report.errors);
    List.iteri (fun i e -> if i < 10 then Printf.printf "  ERROR %s\n" e) report.errors;
    let sim = Sim.create lib nl in
    let rise, fall, bad = Sim.classify_clocks sim ~clock:"clk" in
    Printf.printf "gates: %d primitive gates, %d flip-flops, %d macros; clock edges: %d rising, %d falling, %d unresolved\n%!"
      (Array.length sim.gates) (Array.length sim.ffs) (Array.length sim.mems) rise fall (List.length bad);
    if bad <> [] then failwith (List.hd bad);
    let port p = match Hashtbl.find_opt sim.port p with Some s -> s | None -> failwith ("no port " ^ p) in
    sim.v.(port "ena") <- 1;
    { sim; rst = port "rst_n";
      ins = Array.init n_pads (fun i -> port (if i < 8 then Printf.sprintf "ui_in[%d]" i else Printf.sprintf "uio_in[%d]" (i - 8)));
      outs = Array.init 24 (fun i -> port (Printf.sprintf "%s[%d]" (match i / 8 with 0 -> "uo_out" | 1 -> "uio_out" | _ -> "uio_oe") (i mod 8))) }

  let set t ~rst_n ~pads =
    t.sim.v.(t.rst) <- rst_n;
    Array.iteri (fun i s -> t.sim.v.(s) <- (pads lsr i) land 1) t.ins

  let outputs t = Array.fold_left (fun (acc, k) s -> (acc lor (t.sim.v.(s) lsl k), k + 1)) (0, 0) t.outs |> fst

  let reset t =
    Sim.reset t.sim;
    t.sim.v.(Hashtbl.find t.sim.port "ena") <- 1
end

