(* line trace of host fw vs model device around the first command *)
open Ps2_bench
let () =
  let rise = Sim.us 2. in
  let clk = Sim.Oc.create ~rise and data = Sim.Oc.create ~rise in
  let prog, _, find = Ps2_fw.host { clk = 4; data = 5; req = 6 } timing in
  let mem = Array.init 4 (fun t -> if t = 1 then prog else Array.make 256 Isa_v.halt) in
  let app = Pc_app.create [ Sim.us 3000., 0xED ] in
  let port = { fw_clk = 4; fw_data = 5; fw_req = 6; clk; data } in
  let now_ = ref 0 in
  let m, _, seq = seq_agent ~mem ~ports:[ 1, port ] ~rtl:false
      ~req:(fun t -> t = 1 && (app.now <- !now_; Pc_app.req app)) ~host_in:(fun t -> if t = 1 then Pc_app.host_in app else None)
      ~on_out:(fun t v -> if t = 1 then (Printf.printf "%9.1fus   host OUT %02x\n" (float !now_ /. 1e9) v; Pc_app.on_out app v)) in
  let seq = { seq with fire = (fun now -> now_ := now; seq.fire now) } in
  let dev = Ps2_model.Device.create ~clk ~data ~hz:13e3 () in
  dev.queue <- [ 0x33; 0xF0; 0x33 ];
  let model = Sim.agent ~name:"dev" ~hz:Ps2_model.tick_hz (fun now -> Ps2_model.Device.fire dev now) in
  let pv = ref (-1) in
  let tracer = Sim.agent ~name:"tr" ~hz:10e6 (fun now ->
      let c = Sim.Oc.level clk ~now and d = Sim.Oc.level data ~now in
      let v = c * 2 + d in
      if v <> !pv && now > Sim.us 2990. && now < Sim.us 4200. then
        Printf.printf "%9.2fus clk=%d data=%d  (pc %d; clk by %s data by %s)\n" (float now /. 1e9) c d m.st.pcs.(1)
          (String.concat "," (Hashtbl.fold (fun k () a -> k :: a) clk.pulling []))
          (String.concat "," (Hashtbl.fold (fun k () a -> k :: a) data.pulling []));
      pv := v) in
  ignore (Sim.run ~until:(Sim.us 4300.) [ seq; model; tracer ]);
  List.iter (fun l -> Printf.printf "label %s = %d\n" l (find l)) [ "hidle"; "hrx"; "htx"; "hw"; "hgot"; "htE"; "htE_s"; "htO"; "htO_s"; "htE_p"; "htO_p"; "htp"; "htto" ];
  Printf.printf "dev received %s; violations %s\n" (String.concat " " (List.map (fun (_, b, ok) -> Printf.sprintf "%02x:%b" b ok) dev.received))
    (Ps2_model.pp_violations dev.violations)
