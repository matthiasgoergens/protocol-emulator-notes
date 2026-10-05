(* The hazard checker on the JTAG and SWD host firmware (wide variant, translated to v2).
   Declarations from the firmware's own headers: JTAG T0 (driver) owns TCK 0, TMS 1, TDI 2;
   T1 (sampler) reads TCK and TDO 3. SWD T0 owns SWCLK 0 and SWDIO 1 (and reads SWDIO back). *)
open Hazard

let fetch mem = Compat.fetch_threads ~translate:Variant.translate mem
let g r t ks = (r, Thread t, ks)

let () =
  let bad = ref 0 in
  let mem, _ = Jtag_host.programmes Jtag_host.fastest in
  let jd = { no_decl with grants = [ g (Pin 0) 0 [ Pin_drive ]; g (Pin 1) 0 [ Pin_drive ]; g (Pin 2) 0 [ Pin_drive ];
                                     g (Pin 0) 1 [ Pin_sample ]; g (Pin 3) 1 [ Pin_sample ] ] } in
  if report ~name:"JTAG host: T0 vector driver, T1 TDO sampler" ~fetch:(fetch mem) jd <> [] then incr bad;
  let mem, _ = Swd_host.programmes Swd_host.fastest in
  let sd = { no_decl with grants = [ g (Pin 0) 0 [ Pin_drive ]; g (Pin 1) 0 [ Pin_drive; Pin_sample ] ] } in
  if report ~name:"SWD host: T0 transaction engine" ~fetch:(fetch mem) sd <> [] then incr bad;
  (* a planted violation in real firmware: the JTAG sampler thread also drives TDI *)
  let jmem, _ = Jtag_host.programmes Jtag_host.fastest in
  let planted = Array.map Array.copy jmem in
  (* its first word, which is reachable, becomes a SETP on TDI *)
  planted.(1).(0) <- Isa.setp ~mask:(1 lsl 2) ~value:1 ~oe:1;
  let r = report ~name:"control: JTAG with the sampler's first word replaced by a SETP on TDI (must be rejected)" ~fetch:(fetch planted) jd in
  if r = [] then incr bad;
  Printf.printf "HAZARD WIDE %s\n" (if !bad = 0 then "PASS" else "FAIL")
