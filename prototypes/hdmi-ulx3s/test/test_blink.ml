(* The 1 Hz blinker toggles exactly every [half_period] cycles (checked with half_period 5 and 2). *)
open! Base
open Hardcaml

let check half =
  let clock = Signal.input "clock" 1 and clear = Signal.input "clear" 1 in
  let spec = Reg_spec.create ~clock ~clear () in
  let led = Hdmi_hw.Hdmi.blink ~spec ~half_period:half in
  let sim = Cyclesim.create (Circuit.create_exn ~name:"blink" [ Signal.output "led" led ]) in
  let o = Cyclesim.out_port sim "led" in
  Cyclesim.in_port sim "clear" := Bits.vdd; Cyclesim.cycle sim; Cyclesim.in_port sim "clear" := Bits.gnd;
  let last = ref (Bits.to_int !o) and last_t = ref (-1) and gaps = ref [] in
  for t = 0 to 10 * half do
    Cyclesim.cycle sim;
    let v = Bits.to_int !o in
    if v <> !last then (if !last_t >= 0 then gaps := (t - !last_t) :: !gaps; last_t := t; last := v)
  done;
  let ok = (not (List.is_empty !gaps)) && List.for_all !gaps ~f:(fun g -> g = half) in
  Stdio.printf "half_period %d: toggle gaps %s -> %s\n" half
    (String.concat ~sep:" " (List.map (List.rev !gaps) ~f:Int.to_string)) (if ok then "ok" else "FAIL");
  ok

let () = if not (check 5 && check 2) then Stdlib.exit 1
