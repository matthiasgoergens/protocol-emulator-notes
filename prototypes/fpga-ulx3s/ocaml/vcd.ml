(* A trace as a VCD file on a quarter-clock time base, for Surfer or GTKWave.

   Time unit: one quarter clock, written as [quarter_ps] picoseconds (4167 for 60 MHz), so the
   viewer's time axis is real time; cycle c starts at 4c quarters. Signals, as the core sees or
   presents them in each cycle (the stage's one-clock delay to the pads and the samplers'
   two-clock delay back are not undone):
     clk                 high in quarters 0 and 1
     cycle               the cycle number
     pin_out[i], pin_oe[i], pin_in[i]   the clock-grid view, changing at quarter 0
     pin_sub[i]          the level the core asks for in each quarter (bit 4i+p of pin_sub)
     pin_in4[i]          the quarter-p sample of pin i that the core sees in this cycle
     host_out            the byte, with host_out_valid *)

type cyc = { pin_in : int; pin_out : int; pin_oe : int; flags : int; host_out : int; pin_sub : int; pin_in4 : int }

let write oc ~quarter_ps (arr : cyc array) =
  let ids = Hashtbl.create 64 and n_ids = ref 0 in
  let id name = match Hashtbl.find_opt ids name with
    | Some i -> i
    | None ->
      let k = !n_ids in incr n_ids;
      (* printable identifiers from '!' onwards, two characters where needed *)
      let i = if k < 94 then String.make 1 (Char.chr (33 + k))
        else String.init 2 (fun j -> Char.chr (33 + (if j = 0 then k / 94 else k mod 94))) in
      Hashtbl.replace ids name i; i in
  Printf.fprintf oc "$date fpga_tests.exe vcd $end\n$version emu_core trace $end\n$timescale 1ps $end\n";
  Printf.fprintf oc "$scope module emu $end\n";
  let wire w name = Printf.fprintf oc "$var wire %d %s %s $end\n" w (id name) name in
  wire 1 "clk"; wire 32 "cycle";
  List.iter (fun base -> for i = 0 to 7 do wire 1 (Printf.sprintf "%s%d" base i) done)
    [ "pin_out"; "pin_oe"; "pin_in"; "pin_sub"; "pin_in4" ];
  wire 1 "host_out_valid"; wire 8 "host_out";
  Printf.fprintf oc "$upscope $end\n$enddefinitions $end\n";
  let last = Hashtbl.create 64 in
  let emit name w v =
    if Hashtbl.find_opt last name <> Some v then begin
      Hashtbl.replace last name v;
      if w = 1 then Printf.fprintf oc "%d%s\n" v (id name)
      else begin
        let b = Buffer.create w in
        for k = w - 1 downto 0 do Buffer.add_char b (if (v lsr k) land 1 = 1 then '1' else '0') done;
        Printf.fprintf oc "b%s %s\n" (Buffer.contents b) (id name)
      end
    end in
  Array.iteri (fun c e ->
    for p = 0 to 3 do
      Printf.fprintf oc "#%d\n" ((4 * c + p) * quarter_ps);
      emit "clk" 1 (if p < 2 then 1 else 0);
      if p = 0 then begin
        emit "cycle" 32 c;
        for i = 0 to 7 do
          emit (Printf.sprintf "pin_out%d" i) 1 ((e.pin_out lsr i) land 1);
          emit (Printf.sprintf "pin_oe%d" i) 1 ((e.pin_oe lsr i) land 1);
          emit (Printf.sprintf "pin_in%d" i) 1 ((e.pin_in lsr i) land 1)
        done;
        emit "host_out_valid" 1 (e.flags land 1);
        emit "host_out" 8 e.host_out
      end;
      for i = 0 to 7 do
        emit (Printf.sprintf "pin_sub%d" i) 1 ((e.pin_sub lsr (4 * i + p)) land 1);
        emit (Printf.sprintf "pin_in4%d" i) 1 ((e.pin_in4 lsr (4 * i + p)) land 1)
      done
    done) arr;
  Printf.fprintf oc "#%d\n" (4 * Array.length arr * quarter_ps)
