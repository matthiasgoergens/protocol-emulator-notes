(* The specification as a circuit with the RTL core's interface: registers for Isa2's state, the
   interpreter (Isa2.Make (Hw_value)) as the next-state logic, and the same port timing as
   sequencer2.ml (fetch address of the next thread presented in this clock; host, port and FINE
   outputs registered; bank strobes and ready pulses combinational).

   The interpreter treats the executing thread as a known number, so the circuit has four copies
   of it, one per thread, and the thread register selects one ([H.merge]). Host control is applied
   after the clock, as Isa2.exec applies io.host_ctl; it is the only line of semantics written
   here rather than taken from Isa2 (the hardware's thread index is a signal, Isa2's an int). *)
open Hardcaml
open Signal

module H = Isa2.Make (Hw_value)

type outputs = {
  imem_addr : t; pin_out : t; pin_oe : t; pin_sub : t;
  host_out : t; host_tag : t; host_out_valid : t; host_in_ready : t;
  port_out_data : t; port_out_valid : t; port_in_ready : t;
  bank_addr : t; bank_we : t; bank_re : t; bank_wdata : t;
  fine_out : t; fine_valid : t; cfg_out : t;
  state : H.state; thread : t;              (* the registers, for the state comparison *)
}

let cat l = concat_msb (List.rev l)   (* thread 0 at the least significant end, as sequencer2.ml *)

let merge_effects g (x : H.effects) (y : H.effects) : H.effects =
  let i = mux2 g in
  let two (a, b) (a', b') = (i a a', i b b') and three (a, b, c) (a', b', c') = (i a a', i b b', i c c') in
  { host_out = three x.host_out y.host_out; host_in_ready = i x.host_in_ready y.host_in_ready;
    port_pop = two x.port_pop y.port_pop; port_push = three x.port_push y.port_push;
    bank_write = three x.bank_write y.bank_write; bank_read = two x.bank_read y.bank_read;
    fine_out = two x.fine_out y.fine_out; pins_written = i x.pins_written y.pins_written }

let create ~clock ~clear ~imem_data ~pin_in ~pin_in4 ~host_in ~host_in_valid ~port_in ~port_in_valid
    ~port_out_ready ~flags ~ctl_valid ~ctl_thread ~ctl_page ~ctl_pc ~boot_page ~boot_pc ~bank_rd =
  let spec = Reg_spec.create ~clock () in
  (* a register [q] whose input [d] is driven at the end; clear loads [init] *)
  let pending = ref [] in
  let mk ?init w =
    let d = wire w in
    let q = reg spec d in
    pending := (d, Option.value init ~default:(zero w)) :: !pending;
    (q, d) in
  let per ?init w = Array.init Isa2.n_threads (fun t -> mk ?init:(Option.map (fun f -> f t) init) w) in
  let pcs = per 8 ~init:(fun t -> select boot_pc (8 * t + 7) (8 * t)) in
  let pages = per 2 ~init:(fun t -> select boot_page (2 * t + 1) (2 * t)) in
  let accs = per 8 and cnts = per 12 and dls = per 12 and bps = per 10 and fines = per 8 and armed = per 1 in
  let cfgs = per 8 and lsend = per 3 and inbox = per 8 and full = per 1 in
  let pin_out = mk 8 and pin_oe = mk 8 and pin_sub = mk 32 and latch = mk 8 and thread = mk 2 in
  let q a = Array.map fst a in
  let st : H.state =
    { pcs = q pcs; pages = q pages; accs = q accs; cnts = q cnts; dls = q dls; bps = q bps; fines = q fines;
      armed = q armed; cfgs = q cfgs; lsend = q lsend; inbox = q inbox; full = q full;
      pin_out = fst pin_out; pin_oe = fst pin_oe; thread = 0; pin_sub = fst pin_sub; latch = fst latch;
      bankmem = { rd = bank_rd; we = gnd; waddr = zero 10; wdata = zero 8 } } in
  let io : H.io =
    { pin_in; pin_in4; host_in; host_in_valid; port_in;
      port_in_valid = Array.init 4 (bit port_in_valid); port_out_ready = Array.init 4 (bit port_out_ready);
      flags; host_ctl = None } in
  let runs = List.init Isa2.n_threads (fun t ->
      let s = H.copy st in
      s.thread <- t;
      let e = H.exec s ~instr:imem_data io in
      (t, s, e)) in
  let next, e =
    match List.rev runs with
    | (_, s3, e3) :: rest ->
      List.fold_left (fun (s, e) (t, s_t, e_t) ->
          let g = fst thread ==:. t in
          let s_t = { s_t with H.thread = s.H.thread } in
          (H.merge g s_t s, merge_effects g e_t e)) (s3, e3) rest
    | [] -> assert false in
  for ht = 0 to Isa2.n_threads - 1 do
    let c = ctl_valid &: (ctl_thread ==:. ht) in
    next.pages.(ht) <- mux2 c ctl_page next.pages.(ht);
    next.pcs.(ht) <- mux2 c ctl_pc next.pcs.(ht)
  done;
  let drive (_, d) v = d <== mux2 clear (List.assq d !pending) v in
  let drive_all a v = Array.iteri (fun t r -> drive r v.(t)) a in
  drive_all pcs next.pcs; drive_all pages next.pages; drive_all accs next.accs; drive_all cnts next.cnts;
  drive_all dls next.dls; drive_all bps next.bps; drive_all fines next.fines; drive_all armed next.armed;
  drive_all cfgs next.cfgs; drive_all lsend next.lsend; drive_all inbox next.inbox; drive_all full next.full;
  drive pin_out next.pin_out; drive pin_oe next.pin_oe; drive pin_sub next.pin_sub; drive latch next.latch;
  drive thread (fst thread +:. 1);
  let regc w v = reg (Reg_spec.create ~clock ~clear ()) (uresize v w) in
  let hv, htag, hbyte = e.host_out and pushv, pslot, pbyte = e.port_push and popv, popslot = e.port_pop in
  let fv, fbyte = e.fine_out and we, waddr, wdata = e.bank_write and re, raddr = e.bank_read in
  let onehot v slot = mux2 v (binary_to_onehot slot) (zero 4) in
  let tnext = fst thread +:. 1 in
  { imem_addr = mux tnext (List.init Isa2.n_threads (fun t -> H.fetch_addr next t));
    pin_out = fst pin_out; pin_oe = fst pin_oe; pin_sub = fst pin_sub;
    host_out = regc 8 hbyte; host_tag = regc 3 htag; host_out_valid = regc 1 hv; host_in_ready = e.host_in_ready;
    port_out_data = regc 8 pbyte; port_out_valid = regc 4 (onehot pushv pslot); port_in_ready = onehot popv popslot;
    bank_addr = mux2 we waddr raddr; bank_we = we; bank_re = re; bank_wdata = wdata;
    fine_out = regc 8 fbyte; fine_valid = regc 1 fv; cfg_out = cat (Array.to_list st.cfgs);
    state = st; thread = fst thread }
