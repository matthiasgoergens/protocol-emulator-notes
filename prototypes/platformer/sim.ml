(* Cyclesim harness: the chip plus the host. The host (the RP2350, here OCaml) writes the next
   line's entries into the line buffer during the current line, one entry every [wstride] clocks,
   starting when it sees the line_go pin fall; it refreshes the lookup table four entries per line.

   Host link: an entry is 19 bits, sent as five 4-bit nibbles on the pin sampler's clocked mode
   (../pin-sampler), one nibble per strobe edge, strobe edges every 2 clocks: 10 clocks per entry
   at most. [wstride] = 10 models exactly that rate. *)
open Hardcaml

let wstride = 10
let cpl = Vprog.cpl and lpf = Vprog.lpf
let first_vis = 40 and nvis = 240

type t = {
  sim : Cyclesim.t_port_list;
  clear : Bits.t ref; cfg_in : Bits.t ref; cfg_strobe : Bits.t ref; hw_en : Bits.t ref; hw_data : Bits.t ref;
  pins : Bits.t ref; seq : Bits.t ref; arr_tag : Bits.t ref; arr_data : Bits.t ref;
  lut_we : Bits.t ref; lut_waddr : Bits.t ref;
}

let make ?fault () =
  let sim = Cyclesim.create (Video.circuit ?fault ()) in
  let i = Cyclesim.in_port sim and o = Cyclesim.out_port sim in
  let s = { sim; clear = i "clear"; cfg_in = i "cfg_in"; cfg_strobe = i "cfg_strobe"; hw_en = i "hw_en";
            hw_data = i "hw_data"; pins = o "pins"; seq = o "seq_pins"; arr_tag = o "arr_tag";
            arr_data = o "arr_data"; lut_we = o "lut_we"; lut_waddr = o "lut_waddr" } in
  (* configure the PE row (the last PE's bytes first), then reset the rest *)
  let cfgs = Array.init Video.npe (fun k -> if k < Video.kcells then Pex_model.tile_cfg ~kcells:Video.kcells else Pex_model.sprite_cfg) in
  s.cfg_strobe := Bits.vdd;
  for k = Video.npe - 1 downto 0 do
    Array.iter (fun b -> s.cfg_in := Bits.of_int ~width:8 b; Cyclesim.cycle sim) cfgs.(k)
  done;
  s.cfg_strobe := Bits.gnd;
  s.clear := Bits.vdd; Cyclesim.cycle sim; s.clear := Bits.gnd;
  s

(* LUT entries *)
let lut_entry ~hue ~luma =
  let code = 4 + max 0 (min 10 luma) in
  if hue = 0 then code
  else code lor ((((hue - 1) * 256 + 6) / 12) lsl 4) lor (1 lsl 12) lor (1 lsl 13)
let burst_entry = 4 lor (85 lsl 4) lor (1 lsl 12)

type stats = { mutable lut_age_max : int; mutable entries_max : int; mutable entries_sum : int;
               mutable lines_sent : int; mutable vis_entries_max : int }

(* Run [fields] fields. [packet ~field ~line] returns the entries for a line (without the LUT
   refresh, which is added here from [lut ()]). [on_cycle] sees every cycle. *)
let run s ~fields ~(lut : unit -> int array) ~(packet : field:int -> line:int -> (int * int) list) ~on_cycle =
  let st = { lut_age_max = 0; entries_max = 0; entries_sum = 0; lines_sent = 0; vis_entries_max = 0 } in
  let field = ref 0 and line = ref 0 and prev_go = ref 0 and global = ref 0 and prev_field = ref 0 in
  let pending = ref [||] and wstart = ref max_int in
  let last_write = Array.make 64 (-1) in
  let cyc = ref 0 in
  while !field < fields do
    (* host writes *)
    let k = !cyc - !wstart in
    if k >= 0 && k mod wstride = 0 && k / wstride < Array.length !pending then begin
      let tg, d = !pending.(k / wstride) in
      s.hw_en := Bits.vdd; s.hw_data := Bits.of_int ~width:Video.entry_bits ((tg lsl 16) lor (d land 0xFFFF))
    end else s.hw_en := Bits.gnd;
    Cyclesim.cycle s.sim;
    let seq = Bits.to_int !(s.seq) in
    let go_n = (seq lsr 4) land 1 in
    if !prev_go = 1 && go_n = 0 then begin
      (* a new line has started: which one? *)
      let field_n = (seq lsr 5) land 1 in
      let next = (!line + 1) mod lpf in
      (* the field pin is low from the start of line 0 to h 248 of line 3 *)
      let starts_field = field_n = 0 && !prev_field = 1 in
      if (next = 0) <> starts_field && !global > 0 then failwith (Printf.sprintf "field pin disagrees at line %d" next);
      prev_field := field_n;
      if next = 0 then incr field;
      line := next;
      incr global;
      (* send the packet for the following line *)
      let target = (next + 1) mod lpf in
      let tfield = if target = 0 then !field + 1 else !field in
      let l = lut () in
      let m = !global mod 16 in
      let refresh = Scene.lut_record ~addr:(4 * m) (List.init 4 (fun i -> l.(4 * m + i))) in
      let p = Array.of_list (refresh @ packet ~field:tfield ~line:target) in
      let n = Array.length p in
      if n > 1 lsl Video.bank_bits then failwith "packet overflows the bank";
      st.entries_max <- max st.entries_max n; st.entries_sum <- st.entries_sum + n; st.lines_sent <- st.lines_sent + 1;
      if target >= first_vis && target < first_vis + nvis then st.vis_entries_max <- max st.vis_entries_max n;
      pending := p; wstart := !cyc + 4
    end;
    prev_go := go_n;
    if Bits.to_int !(s.lut_we) = 1 then last_write.(Bits.to_int !(s.lut_waddr)) <- !cyc;
    let tag = Bits.to_int !(s.arr_tag) in
    let use_idx = if tag = 1 then Some (Bits.to_int !(s.arr_data) land 63)
      else if (seq lsr 7) land 1 = 1 then Some 63 else None in
    (match use_idx with
     | Some i when !field > 0 || !line >= 20 ->
       if last_write.(i) < 0 then failwith (Printf.sprintf "LUT entry %d read before written" i);
       st.lut_age_max <- max st.lut_age_max (!cyc - last_write.(i))
     | _ -> ());
    on_cycle s ~field:!field ~line:!line;
    incr cyc
  done;
  st

let print_stats st =
  Printf.sprintf "line packets: %d sent, mean %.1f entries, max %d (visible lines max %d); \
                  oldest lookup-table entry read: %d clocks = %.3f ms\n"
    st.lines_sent (float st.entries_sum /. float st.lines_sent) st.entries_max st.vis_entries_max
    st.lut_age_max (float st.lut_age_max /. 53.203425e3)
