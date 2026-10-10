(* Waveform files of a run.

   - VCD (IEEE 1364 value change dump), for Surfer and GTKWave: the eight nets at quarter-clock
     resolution, each thread's pc, the OUT bytes to the host, and the clock count.
   - A sigrok trace as tools/sigrok-judge reads it: one byte per clock, bit k = net k (its level
     in the clock's last quarter), with a .expected file written by whoever judges it.
   - A sigrok session file (.sr) that PulseView opens directly: a zip with "version", "metadata"
     and "logic-1-1" (the same bytes), stored uncompressed. *)

type trace = {
  t0 : int;                                  (* the run clock of the first entry *)
  nets : int array array;                    (* per clock, the 8 nets' nibbles *)
  pcs : int array array;                     (* per clock, the 4 threads' (page lsl 8) lor pc *)
  outs : (int * int * int) list;             (* (run clock, tag, byte) *)
  clock_hz : int;
}

(* ---- VCD ---- *)

let ps_of_quarter q = (q * 50000 + 6) / 12      (* 60 MHz: a quarter is 4,166.67 ps *)

let vcd path tr =
  let oc = open_out path in
  let p fmt = Printf.fprintf oc fmt in
  p "$date %s $end\n$version seqasm runner $end\n$timescale 1ps $end\n" "(run)";
  p "$comment one clock is %d Hz; time 0 is run clock %d; nets at quarter-clock resolution $end\n" tr.clock_hz tr.t0;
  p "$scope module chip $end\n";
  for k = 0 to 7 do p "$var wire 1 n%d net%d $end\n" k k done;
  for t = 0 to 3 do p "$var wire 10 t%d pc%d $end\n" t t done;
  p "$var wire 8 ob out_byte $end\n$var wire 3 ot out_tag $end\n$var wire 1 os out_strobe $end\n";
  p "$var integer 32 ck run_clock $end\n";
  p "$upscope $end\n$enddefinitions $end\n";
  let bin w v = String.init w (fun i -> if (v lsr (w - 1 - i)) land 1 = 1 then '1' else '0') in
  let last_net = Array.make 8 (-1) and last_pc = Array.make 4 (-1) in
  let outs = Hashtbl.create 64 in
  List.iter (fun (c, tag, b) -> Hashtbl.replace outs c (tag, b)) tr.outs;
  let strobe = ref (-1) in
  Array.iteri (fun i nets ->
      let c = tr.t0 + i in
      for q = 0 to 3 do
        let changes = Buffer.create 64 in
        for k = 0 to 7 do
          let v = (nets.(k) lsr q) land 1 in
          if v <> last_net.(k) then (Printf.bprintf changes "%dn%d\n" v k; last_net.(k) <- v)
        done;
        if q = 0 then begin
          for t = 0 to 3 do
            let v = tr.pcs.(i).(t) in
            if v <> last_pc.(t) then (Printf.bprintf changes "b%s t%d\n" (bin 10 v) t; last_pc.(t) <- v)
          done;
          (match Hashtbl.find_opt outs c with
           | Some (tag, b) -> Printf.bprintf changes "b%s ob\nb%s ot\n1os\n" (bin 8 b) (bin 3 tag); strobe := 1
           | None -> if !strobe <> 0 then (Buffer.add_string changes "0os\n"; strobe := 0));
          Printf.bprintf changes "b%s ck\n" (bin 32 (c land 0xFFFF_FFFF))
        end;
        if Buffer.length changes > 0 then begin
          p "#%d\n" (ps_of_quarter ((4 * i) + q));
          Buffer.output_buffer oc changes
        end
      done) tr.nets;
  p "#%d\n" (ps_of_quarter (4 * Array.length tr.nets));
  close_out oc

(* ---- sigrok ---- *)

let logic_bytes tr = String.init (Array.length tr.nets) (fun i ->
    let v = ref 0 in
    for k = 0 to 7 do v := !v lor (((tr.nets.(i).(k) lsr 3) land 1) lsl k) done;
    Char.chr !v)

let sigrok_bin path tr =
  let oc = open_out_bin path in
  output_string oc (logic_bytes tr);
  close_out oc

(* CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320), as the zip format requires *)
let crc32 s =
  let table = Array.init 256 (fun n ->
      let c = ref n in
      for _ = 0 to 7 do c := if !c land 1 = 1 then 0xEDB88320 lxor (!c lsr 1) else !c lsr 1 done; !c) in
  let c = ref 0xFFFFFFFF in
  String.iter (fun ch -> c := table.((!c lxor Char.code ch) land 0xFF) lxor (!c lsr 8)) s;
  !c lxor 0xFFFFFFFF

(* a zip archive with stored (uncompressed) entries *)
let zip path (files : (string * string) list) =
  let b = Buffer.create 4096 in
  let u16 v = Buffer.add_char b (Char.chr (v land 0xFF)); Buffer.add_char b (Char.chr ((v lsr 8) land 0xFF)) in
  let u32 v = u16 (v land 0xFFFF); u16 ((v lsr 16) land 0xFFFF) in
  let central = Buffer.create 512 in
  let c16 v = Buffer.add_char central (Char.chr (v land 0xFF)); Buffer.add_char central (Char.chr ((v lsr 8) land 0xFF)) in
  let c32 v = c16 (v land 0xFFFF); c16 ((v lsr 16) land 0xFFFF) in
  List.iter (fun (name, data) ->
      let off = Buffer.length b and crc = crc32 data and n = String.length data in
      u32 0x04034b50; u16 20; u16 0; u16 0; u16 0; u16 0x21; u32 crc; u32 n; u32 n; u16 (String.length name); u16 0;
      Buffer.add_string b name; Buffer.add_string b data;
      c32 0x02014b50; c16 20; c16 20; c16 0; c16 0; c16 0; c16 0x21; c32 crc; c32 n; c32 n;
      c16 (String.length name); c16 0; c16 0; c16 0; c16 0; c32 0; c32 off;
      Buffer.add_string central name) files;
  let cd_off = Buffer.length b and cd_len = Buffer.length central in
  Buffer.add_buffer b central;
  u32 0x06054b50; u16 0; u16 0; u16 (List.length files); u16 (List.length files); u32 cd_len; u32 cd_off; u16 0;
  let oc = open_out_bin path in
  Buffer.output_buffer oc b;
  close_out oc

let sigrok_session path tr =
  let meta = Buffer.create 256 in
  Printf.bprintf meta "[global]\nsigrok version=0.5.2\n\n[device 1]\ncapturefile=logic-1\ntotal probes=8\nsamplerate=%d Hz\ntotal analog=0\n" tr.clock_hz;
  for k = 0 to 7 do Printf.bprintf meta "probe%d=net%d\n" (k + 1) k done;
  Buffer.add_string meta "unitsize=1\n";
  zip path [ ("version", "2"); ("metadata", Buffer.contents meta); ("logic-1-1", logic_bytes tr) ]
