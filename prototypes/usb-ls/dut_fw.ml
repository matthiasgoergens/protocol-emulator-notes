(* The firmware device behind the bench's device interface: two complete systems, the
   interpreter-based model and the RTL, each with its own programme memory and controller, fed
   the same bus every clock and compared on every clock (pins, output enables, host port). The
   bench is driven by the RTL. *)

type t0cfg = Firmware.t0_cfg
type sys = { img : Firmware.images; ctl : Controller.t }

let make ?(name = "firmware") ?trace ?t0cfg ?t12cfg ?(jk_swap = false) ?latency ?refill ?depth ?prepare ?(verbose_mismatch = true) () =
  let mk () =
    let img = Firmware.build ?t0cfg ?t12cfg () in
    let ctl = Controller.create ~jk_swap ?latency ?refill ?depth ?prepare img in
    Controller.init ctl; { img; ctl } in
  let a = mk () and b = mk () in
  let model = Fw_sys.Model.create () in
  let rtl = Fw_sys.Rtl_sim.create () in
  let mismatches = ref 0 and cycles = ref 0 in
  let drive (po, poe) =
    let oe_dp = poe land 1 and oe_dm = (poe lsr 1) land 1 in
    let dp = if oe_dp = 1 then po land 1 else 0 and dm = if oe_dm = 1 then (po lsr 1) land 1 else 1 in
    dp, dm, (if oe_dp = 1 || oe_dm = 1 then 1 else 0) in
  let step ~dp ~dm =
    incr cycles;
    let feed (s : sys) = Controller.rdy s.ctl, Controller.head s.ctl in
    let rdy_a, head_a = feed a and rdy_b, head_b = feed b in
    let ea = Fw_sys.Model.step model ~mem:a.img.mem ~dp ~dm ~rdy:rdy_a ~host_in:head_a ~host_in_valid:(rdy_a = 1) in
    let eb = Fw_sys.Rtl_sim.step rtl ~mem:b.img.mem ~dp ~dm ~rdy:rdy_b ~host_in:head_b ~host_in_valid:(rdy_b = 1) in
    let pa = model.st.pin_out, model.st.pin_oe and pb = Fw_sys.Rtl_sim.pins rtl in
    let same = pa = pb && ea.host_out = eb.host_out && ea.host_in_ready = eb.host_in_ready
               && Array.to_list model.st.pcs = Fw_sys.Rtl_sim.pcs rtl in
    if not same then begin
      incr mismatches;
      if verbose_mismatch && !mismatches <= 3 then
        Printf.printf "    [%s] lockstep mismatch at clock %d: model pins %02x/%02x pcs %s, rtl pins %02x/%02x pcs %s\n" name !cycles
          (fst pa) (snd pa) (String.concat "," (Array.to_list (Array.map string_of_int model.st.pcs)))
          (fst pb) (snd pb) (String.concat "," (List.map string_of_int (Fw_sys.Rtl_sim.pcs rtl)))
    end;
    (match trace with Some f -> f !cycles ~dp ~dm model a | None -> ());
    Controller.tick a.ctl ~emitted:ea.host_out ~popped:ea.host_in_ready;
    Controller.tick b.ctl ~emitted:eb.host_out ~popped:eb.host_in_ready in
  let out () = drive (Fw_sys.Rtl_sim.pins rtl) in
  let offer_report r = Controller.offer_report a.ctl r; Controller.offer_report b.ctl r in
  { Bench.name; step; out; offer_report; nak_ok = true; mismatches = (fun () -> !mismatches) }, a, b
