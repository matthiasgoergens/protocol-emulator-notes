(* The hardened chip's GDS, extracted to gates by ../postlayout-roundtrip, against this
   directory's Hardcaml, clock by clock and pin by pin.

   gate_lockstep.exe GDS MODELS.v SIZES TRIALS CYCLES SEED [MODE] [PLANT...]

   GDS is the final GDS of a harden (top cell tt_um_chip_top), MODELS.v the PDK's standard-cell
   Verilog (the SRAM macros' models are found next to it), SIZES the layout it was hardened with
   (1,1,1,1 or 2,2,2,2; 512-word store as in tt/). MODE:

   - two-edge (default): the gate netlist clocked edge by edge, each flip-flop on the edge its
     clock pin is wired to (Sim.classify_clocks: through buffers and inverters back to clk), as
     the silicon runs. The reference is the same Hardcaml as Tt_top.create, in two parts: the
     rising-edge part (Tt_top.reset_sync and Tt_top.core_side) and the four-phase stage
     (Mphase.Stage.circuit_substep), whose phases 0 and 1 are enabled on the rising edge and 2
     and 3 on the falling edge, exactly the [| clk; clk; ~clk; ~clk |] of Tt_top.create. Every
     output pin is compared after both edges.
   - single-edge: the gate netlist with every flip-flop on one edge (Sim.cycle) against
     Tt_top.create in Cyclesim, which also clocks every register at once. Same logic, not the
     silicon's timing; it checks the two-edge reference's harness from the other side.
   - harness: no gates; the two-part reference with all four phases on one edge against
     Tt_top.create in Cyclesim. This is the check that the two-part reference is Tt_top.

   The memories: in the gates, IHP's SRAM models as Sim models them (macros.ml); in Hardcaml,
   Chip_rtl.behavioural_mem, which sim/macro_check.sh found equal to IHP's functional models
   (write-through, read every clock), read for read.

   Stimulus: Host (src/host.ml) drives the host link on uio[5:0] with random transactions:
   programme and bank writes and read-backs while stopped, register writes, FIFO traffic, PE
   configuration bytes, run phases of random length; ui_in and uio[7:6] toggle at random rates,
   ui_in also between the two edges; rst_n is pulsed now and then. The read-backs are also
   checked against what was written, which tests the memories end to end through the pins.

   PLANT (controls, in the extracted netlist, not the GDS): fall2rise:K puts the K-th
   falling-edge flip-flop on the rising edge. *)

open Twoedge

(* ---- stimulus ---- *)

type stim = {
  rng : Random.State.t;
  host : Host.t;
  mutable running : bool;
  prog : int option array;   (* programme store bytes as written, None = unknown *)
  bank : int option array;
  mutable readback_bytes : int;
  mutable readback_wrong : int;
  mutable txns : int;
  mutable written : (int * int * int) list;   (* (target, address, length), most recent first *)
}

let prog_bytes = 2 * 512

let new_txn st =
  let r = st.rng in
  let rnd n = Random.State.int r n in
  let bytes n = List.init n (fun _ -> rnd 256) in
  let read tgt addr n shadow =
    Host.submit st.host
      (Host.Read { tgt; addr; n; k = (fun got ->
           List.iteri (fun i v ->
             match shadow with
             | Some sh -> (match sh.(addr + i) with
                 | Some w -> st.readback_bytes <- st.readback_bytes + 1;
                   if w <> v then st.readback_wrong <- st.readback_wrong + 1
                 | None -> ())
             | None -> ()) got) }) in
  st.txns <- st.txns + 1;
  if st.running then begin
    (* while running: idle, FIFO traffic, status reads, then stop *)
    match rnd 6 with
    | 0 -> Host.submit st.host (Host.Write { tgt = Regs.t_reg; addr = Regs.r_ctrl; data = [ 2 * rnd 2 ] });
      st.running <- false;
      Array.fill st.bank 0 (Array.length st.bank) None   (* the threads' STB may have written it *)
    | 1 | 2 -> Host.submit st.host (Host.Write { tgt = Regs.t_hostin; addr = 0; data = bytes (1 + rnd 4) })
    | 3 -> read Regs.t_hostout 0 (2 * (1 + rnd 3)) None
    | 4 -> read Regs.t_reg (rnd 64) (1 + rnd 4) None
    | 5 -> read Regs.t_sample 0 3 None
    | _ -> Host.submit st.host (Host.Idle (20 + rnd 600))
  end
  else begin
    match rnd 20 with
    | 0 | 1 | 2 ->
      (* whole words: a word is written with its high byte *)
      let n = 2 * (1 + rnd 8) in
      let addr = 2 * rnd ((prog_bytes - n) / 2) in
      let d = bytes n in
      List.iteri (fun i v -> st.prog.(addr + i) <- Some v) d;
      st.written <- (Regs.t_prog, addr, n) :: st.written;
      Host.submit st.host (Host.Write { tgt = Regs.t_prog; addr; data = d })
    | 3 | 4 ->
      (* half the read-backs cover something written earlier *)
      (match List.filter (fun (t, _, _) -> t = Regs.t_prog) st.written with
       | _ :: _ as l when rnd 2 = 0 ->
         let _, a, n = List.nth l (min (rnd 4) (List.length l - 1)) in
         read Regs.t_prog a n (Some st.prog)
       | _ ->
         let n = 1 + rnd 16 in
         read Regs.t_prog (rnd (prog_bytes - n)) n (Some st.prog))
    | 5 | 6 ->
      let n = 1 + rnd 16 in
      let addr = rnd (Chip_spec.bank_bytes - n) in
      let d = bytes n in
      List.iteri (fun i v -> st.bank.(addr + i) <- Some v) d;
      st.written <- (Regs.t_bank, addr, n) :: st.written;
      Host.submit st.host (Host.Write { tgt = Regs.t_bank; addr; data = d })
    | 7 | 8 ->
      (match List.filter (fun (t, _, _) -> t = Regs.t_bank) st.written with
       | _ :: _ as l when rnd 2 = 0 ->
         let _, a, n = List.nth l (min (rnd 4) (List.length l - 1)) in
         read Regs.t_bank a n (Some st.bank)
       | _ ->
         let n = 1 + rnd 16 in
         read Regs.t_bank (rnd (Chip_spec.bank_bytes - n)) n (Some st.bank))
    | 9 | 10 ->
      (* any register but r_ctrl *)
      Host.submit st.host (Host.Write { tgt = Regs.t_reg; addr = 1 + rnd (Regs.reg_space - 1); data = bytes 1 })
    | 11 -> read Regs.t_reg (rnd 64) (1 + rnd 8) None
    | 12 -> Host.submit st.host (Host.Write { tgt = [| Regs.t_pecfg; Regs.t_peinit; Regs.t_peseg; Regs.t_stream; Regs.t_match; Regs.t_hostin |].(rnd 6);
                                              addr = rnd 1024; data = bytes (1 + rnd 8) })
    | 13 -> read [| Regs.t_hostout; Regs.t_sample |].(rnd 2) 0 (1 + rnd 6) None
    | 15 | 16 ->
      (* the assists that put edges at quarter 2 on the output pads (the pin NCO's quarter and
         half grid) or read the input pads' quarter samples (the edge-tracking sampler), on
         random pads, then the assists released: the falling-edge flip-flops of the stage do
         nothing visible otherwise *)
      let w a d = Host.submit st.host (Host.Write { tgt = Regs.t_reg; addr = a; data = d }) in
      w Regs.r_nco_inc (bytes 4);
      for _ = 0 to rnd 4 do
        let pad = List.nth Regs.general_out_pads (rnd (List.length Regs.general_out_pads)) in
        w (Regs.r_padsel pad) [ [| Regs.src_nco_quarter; Regs.src_nco_half; Regs.src_nco_grid; Regs.src_es_bit |].(rnd 4) lor (32 * rnd 4) ]
      done;
      w Regs.r_es_mode [ rnd 16 ];
      w Regs.r_es_pads [ rnd 256 ];
      w Regs.r_es_period [ 1 + rnd 16 ];
      w Regs.r_es_offset [ rnd 16 ];
      w Regs.r_ctrl [ 0 ]
    | 14 ->
      Host.submit st.host (Host.Write { tgt = Regs.t_reg; addr = Regs.r_ctrl; data = [ 1 + 2 * rnd 2 ] });
      st.running <- true
    | _ -> Host.submit st.host (Host.Idle (1 + rnd 40))
  end

(* ---- the run ---- *)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let plants = List.filter (fun a -> String.contains a ':') args in
  let args = List.filter (fun a -> not (String.contains a ':')) args in
  let gds, models, sizes, trials, cycles, seed, mode =
    match args with
    | [ g; m; s; t; c; sd ] -> (g, m, s, int_of_string t, int_of_string c, int_of_string sd, "two-edge")
    | [ g; m; s; t; c; sd; md ] -> (g, m, s, int_of_string t, int_of_string c, int_of_string sd, md)
    | _ -> prerr_endline "usage: gate_lockstep.exe GDS MODELS.v SIZES TRIALS CYCLES SEED [two-edge|single-edge|harness] [fall2rise:K]"; exit 2 in
  let sizes = Array.of_list (List.map int_of_string (String.split_on_char ',' sizes)) in
  let cfg = { Chip_spec.layout = Upe.Spec.layout_of_sizes sizes; prog_words = 512 } in
  Chip_rtl.bug := "";
  let t0 = Unix.gettimeofday () in
  let gates = if mode = "harness" then None else Some (Gates.create ~gds ~models) in
  List.iter (fun p ->
    match String.split_on_char ':' p, gates with
    | [ "fall2rise"; k ], Some g ->
      let falls = List.filter (fun i -> g.sim.ff_fall.(i)) (List.init (Array.length g.sim.ffs) Fun.id) in
      let i = List.nth falls (int_of_string k) in
      g.sim.ff_fall.(i) <- false;
      Printf.printf "plant: %s now takes the rising edge\n" g.sim.ffs.(i).owner
    | _ -> failwith ("plant: " ^ p)) plants;
  Printf.printf "mode %s, layout %s, %d trials x %d clocks, seed %d; set up in %.1f s\n%!" mode
    (String.concat "," (Array.to_list (Array.map string_of_int sizes))) trials cycles seed (Unix.gettimeofday () -. t0);
  let total_mism = ref 0 and total_halves = ref 0 and first = ref [] in
  let toggles = Array.make 24 0 in
  (* how often each flip-flop's Q changed, to show which of the stage's falling-edge flip-flops
     the stimulus exercised *)
  let ff_toggles = match gates with Some g -> Array.make (Array.length g.sim.ffs) 0 | None -> [||] in
  let ff_prev = Array.copy ff_toggles in
  let count_ffs () =
    Option.iter (fun (g : Gates.t) ->
      Array.iteri (fun i (f : Sim.ff) ->
        let q = g.sim.v.(f.q) in
        if q <> ff_prev.(i) then (ff_toggles.(i) <- ff_toggles.(i) + 1; ff_prev.(i) <- q)) g.sim.ffs) gates in
  let rb_bytes = ref 0 and rb_wrong = ref 0 and txns = ref 0 in
  let t1 = Unix.gettimeofday () in
  for trial = 0 to trials - 1 do
    let rng = Random.State.make [| seed; trial |] in
    let st = { rng; host = Host.create (); running = false; prog = Array.make prog_bytes None;
               bank = Array.make Chip_spec.bank_bytes None; readback_bytes = 0; readback_wrong = 0; txns = 0;
               written = [] } in
    Option.iter Gates.reset gates;
    (* fresh simulators: Cyclesim.reset leaves registers without a reset value, and the
       memories, as they were, where Sim.reset starts everything at 0 *)
    let ref1 = if mode = "two-edge" then None else Some (Ref1.create cfg) in
    let ref2 = if mode = "single-edge" then None else Some (Ref2.create cfg) in
    let ui = ref (Random.State.int rng 256) and uio_hi = ref 0 in
    let rate = [| 0.0; 0.01; 0.1; 0.5 |].(Random.State.int rng 4) in
    let rst_low = ref 4 in
    let prev_out = ref 0 and mism = ref 0 in
    for clock = 0 to cycles - 1 do
      (* a reset pulse now and then, only between transactions (the host's S line low) *)
      if !rst_low = 0 && Random.State.int rng 20000 = 0 && Host.idle st.host && st.host.s = 0 then begin
        rst_low := 3; st.running <- false
      end;
      let rst_n = if !rst_low > 0 then (decr rst_low; 0) else 1 in
      let s, r, d = if rst_n = 0 then (st.host.s, st.host.r, st.host.d) else Host.clock st.host ~d_in:((!prev_out lsr 8) land 15) in
      if rst_n = 1 && Host.idle st.host then new_txn st;
      let toggle v w = let x = ref v in for b = 0 to w - 1 do if Random.State.float rng 1.0 < rate then x := !x lxor (1 lsl b) done; !x in
      ui := toggle !ui 8;
      uio_hi := toggle !uio_hi 2;
      let dval = match d with Some v -> v | None -> (!prev_out lsr 8) land 15 in
      let pads () = !ui lor ((dval lor (s lsl 4) lor (r lsl 5) lor (!uio_hi lsl 6)) lsl 8) in
      let compare half got want =
        incr total_halves;
        if got <> want then begin
          incr mism; incr total_mism;
          if List.length !first < 10 then
            first := Printf.sprintf "trial %d clock %d %s: gates %06x, RTL %06x (differ %06x)" trial clock half got want (got lxor want) :: !first
        end;
        count_ffs ();
        let x = got lxor !prev_out in
        for b = 0 to 23 do if (x lsr b) land 1 = 1 then toggles.(b) <- toggles.(b) + 1 done;
        prev_out := got in
      (match mode, gates, ref1, ref2 with
       | "two-edge", Some g, _, Some rf ->
         let p = pads () in
         Gates.set g ~rst_n ~pads:p;
         Sim.edge g.sim ~fall:false;
         Ref2.rise rf ~rst_n ~pads:p ~en:0b0011;
         compare "rise" (Gates.outputs g) (Ref2.outputs rf);
         ui := toggle !ui 8;
         let p = pads () in
         Gates.set g ~rst_n ~pads:p;
         Sim.edge g.sim ~fall:true;
         Ref2.fall rf ~pads:p;
         compare "fall" (Gates.outputs g) (Ref2.outputs rf)
       | "single-edge", Some g, Some r1, _ ->
         let p = pads () in
         Gates.set g ~rst_n ~pads:p;
         Sim.cycle g.sim;
         Ref1.cycle r1 ~rst_n ~pads:p;
         compare "clock" (Gates.outputs g) (Ref1.outputs r1)
       | "harness", None, Some r1, Some rf ->
         let p = pads () in
         Ref2.rise rf ~rst_n ~pads:p ~en:0b1111;
         Ref1.cycle r1 ~rst_n ~pads:p;
         compare "clock" (Ref2.outputs rf) (Ref1.outputs r1)
       | _ -> failwith "mode")
    done;
    rb_bytes := !rb_bytes + st.readback_bytes; rb_wrong := !rb_wrong + st.readback_wrong; txns := !txns + st.txns;
    Printf.printf "trial %d: %d mismatching half-clocks; %d transactions; %d read-back bytes checked, %d wrong; toggle rate %.2f\n%!"
      trial !mism st.txns st.readback_bytes st.readback_wrong rate
  done;
  let dt = Unix.gettimeofday () -. t1 in
  List.iter (Printf.printf "  first mismatches: %s\n") (List.rev !first);
  Option.iter (fun (g : Gates.t) ->
    Array.iter (fun (m : Sim.mem) ->
      Printf.printf "macro %s: %d writes, %d reads, %d edges with BIST enabled\n" m.mowner m.writes m.reads m.bist_edges)
      g.sim.mems) gates;
  Option.iter (fun (g : Gates.t) ->
    let count fall = Array.fold_left ( + ) 0 (Array.mapi (fun i _ -> if g.sim.ff_fall.(i) = fall then 1 else 0) g.sim.ffs) in
    let toggled fall = Array.fold_left ( + ) 0 (Array.mapi (fun i c -> if g.sim.ff_fall.(i) = fall && c > 0 then 1 else 0) ff_toggles) in
    Printf.printf "flip-flops whose output changed: %d of %d on the rising edge, %d of %d on the falling edge\n"
      (toggled false) (count false) (toggled true) (count true);
    Array.iteri (fun i (f : Sim.ff) -> if g.sim.ff_fall.(i) then
                    Printf.printf "  falling %s: %d changes\n" f.owner ff_toggles.(i)) g.sim.ffs) gates;
  let never = List.filter (fun b -> toggles.(b) = 0) (List.init 24 Fun.id) in
  Printf.printf "output pins that never toggled: %d of 24 (%s)\n" (List.length never)
    (String.concat " " (List.map (fun b -> Printf.sprintf "%s[%d]" [| "uo_out"; "uio_out"; "uio_oe" |].(b / 8) (b mod 8)) never));
  Printf.printf "%d transactions; read-back through the pins: %d bytes checked against what was written, %d wrong\n"
    !txns !rb_bytes !rb_wrong;
  Printf.printf "%s: %d trials x %d clocks, %d compared output words, %d mismatching (%.0f s, %.0f clocks/s)\n"
    mode trials cycles !total_halves !total_mism dt (Float.of_int (trials * cycles) /. dt);
  if Array.for_all (fun c -> c = 0) toggles then (print_endline "no output ever changed: refusing to call this agreement"; exit 3);
  exit (if !total_mism = 0 && !rb_wrong = 0 then 0 else 1)
