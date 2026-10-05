(* The receive-side analyser: what a TV overlay would show about an incoming S/PDIF stream.
   Input: the receiver's decoded subframes and channel-status blocks (rx.ml's host side) and the
   receiver clock. Output: a fixed-width text panel (40 columns, for the console's text sprites
   later) and the same facts as key=value lines for checks. *)

let cs_field bits lo n = let v = ref 0 in for i = n - 1 downto 0 do v := (!v lsl 1) lor bits.(lo + i) done; !v
(* field as transmitted order, bit lo first: "b_lo b_lo+1 ..." as the standard's tables print it *)
let cs_str bits lo n = String.init n (fun i -> if bits.(lo + i) = 1 then '1' else '0')

let fs_of_code = function
  | "0000" -> "44.1 kHz" | "0100" -> "48 kHz" | "1100" -> "32 kHz" | "0010" -> "22.05 kHz" | "0001" -> "88.2 kHz"
  | "0110" -> "24 kHz" | "0101" -> "96 kHz" | "0011" -> "176.4 kHz" | "0111" -> "192 kHz" | "1000" -> "not indicated"
  | s -> "reserved " ^ s

let category_name c = (* bits 8..14 as a value, bit 8 = LSB *)
  match c with
  | 0x00 -> "general" | 0x01 -> "CD (IEC 60908)" | 0x09 -> "non-IEC 60908 CD" | 0x19 -> "DVD" | 0x49 -> "MiniDisc"
  | 0x02 -> "PCM coder" | 0x03 -> "DAT" | x when x land 7 = 1 -> "laser-optical, other" | x -> Printf.sprintf "0x%02x" x

let describe_cs (b : int array) =
  [ ("use", if b.(0) = 0 then "consumer" else "professional");
    ("audio", if b.(1) = 0 then "linear PCM" else "non-PCM");
    ("copy", if b.(2) = 1 then "permitted (Cp=1)" else "copyright asserted (Cp=0)");
    ("emphasis", (match cs_str b 3 3 with "000" -> "none" | "100" -> "50/15 us" | s -> "reserved " ^ s));
    ("mode", cs_str b 6 2);
    ("category", category_name (cs_field b 8 7));
    ("L bit", string_of_int b.(15));
    ("source", string_of_int (cs_field b 16 4));
    ("channel", (match cs_field b 20 4 with 1 -> "1 (left)" | 2 -> "2 (right)" | 0 -> "unspecified" | n -> string_of_int n));
    ("fs", fs_of_code (cs_str b 24 4));
    ("clock acc", (match cs_str b 28 2 with "00" -> "level II" | "10" -> "level I" | "01" -> "level III" | _ -> "not matched"));
    ("word length", (match b.(32), cs_str b 33 3 with
       | 0, "100" -> "16 bits" | 0, "000" | 1, "000" -> "not indicated" | 1, "101" -> "24 bits" | 1, "100" -> "20 bits"
       | m, s -> Printf.sprintf "max %d, code %s" (if m = 1 then 24 else 20) s)) ]

type report = {
  lines : string list;   (* the panel *)
  measured_fs : float;
  peak_l_dbfs : float; peak_r_dbfs : float;
  cs_left : (string * string) list;
}

let dbfs x = if x <= 0 then neg_infinity else 20. *. log10 (float x /. 8388608.)

let report ~fclk (d : Rx.decoded) =
  let sfs = d.subframes in
  let bs = List.filter (fun (s : Rx.rx_subframe) -> s.kind = KB) sfs in
  let measured_fs = match bs with
    | a :: _ :: _ -> let z = List.nth bs (List.length bs - 1) in
      float (192 * (List.length bs - 1)) *. fclk /. float (z.at - a.at)
    | _ -> nan in
  let peak k = List.fold_left (fun m (s : Rx.rx_subframe) ->
      if (k = 0 && s.kind <> KW) || (k = 1 && s.kind = KW) then max m (abs (Iec60958.sign24 ((s.slots lsr 4) land 0xffffff))) else m) 0 sfs in
  let pl = peak 0 and pr = peak 1 in
  let par = List.length (List.filter (fun (s : Rx.rx_subframe) -> s.parity_bad) sfs) in
  let inval = List.length (List.filter (fun (s : Rx.rx_subframe) -> (s.slots lsr 28) land 1 = 1) sfs) in
  let cs = match d.cs_blocks with (_, l, _) :: _ -> describe_cs l | [] -> [] in
  let pad s = if String.length s >= 40 then String.sub s 0 40 else s ^ String.make (40 - String.length s) ' ' in
  let bar db = let n = if db = neg_infinity then 0 else max 0 (min 24 (int_of_float ((db +. 60.) /. 60. *. 24.))) in
    String.make n '#' ^ String.make (24 - n) '.' in
  let lines =
    [ "S/PDIF ANALYSER";
      Printf.sprintf "rate   %.1f Hz (measured)" measured_fs;
      Printf.sprintf "frames %d  blocks %d" (List.length sfs / 2) (List.length d.cs_blocks);
      Printf.sprintf "errors parity %d  framing %d  invalid %d" par (d.count_errors + d.prefix_errors + d.short_records) inval;
      Printf.sprintf "L %s %6.1f dBFS" (bar (dbfs pl)) (dbfs pl);
      Printf.sprintf "R %s %6.1f dBFS" (bar (dbfs pr)) (dbfs pr);
      "channel status (left):" ]
    @ List.map (fun (k, v) -> Printf.sprintf "  %-11s %s" k v) cs in
  { lines = List.map pad lines; measured_fs; peak_l_dbfs = dbfs pl; peak_r_dbfs = dbfs pr; cs_left = cs }
