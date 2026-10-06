(* Planted faults: write a copy of a GDS with one element removed (a cut) or
   one rectangle added (a short), so that the whole round trip, parser
   included, runs on a damaged layout exactly as it runs on the real one. *)

let read_bytes path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let write_bytes path s =
  let oc = open_out_bin path in
  output_string oc s;
  close_out oc

let u16 v = String.init 2 (fun i -> Char.chr ((v lsr (8 * (1 - i))) land 0xff))
let i32 v = String.init 4 (fun i -> Char.chr ((v asr (8 * (3 - i))) land 0xff))

let boundary ~layer ~datatype (x0, y0, x1, y1) =
  let pts = [ (x0, y0); (x1, y0); (x1, y1); (x0, y1); (x0, y0) ] in
  String.concat ""
    [ u16 4; u16 0x0800;
      u16 6; u16 0x0d02; u16 layer;
      u16 6; u16 0x0e02; u16 datatype;
      u16 (4 + 8 * List.length pts); u16 0x1003;
      String.concat "" (List.map (fun (x, y) -> i32 x ^ i32 y) pts);
      u16 4; u16 0x1100 ]

(* Remove the element occupying bytes [start, stop). *)
let cut ~src ~dst ~(elem : Gds.elem) =
  let s = read_bytes src in
  write_bytes dst (String.sub s 0 elem.estart ^ String.sub s elem.eend (String.length s - elem.eend))

(* Add a rectangle (in dbu) to the cell whose ENDSTR is at [endstr]. *)
let add_rect ~src ~dst ~endstr ~layer ~datatype rect =
  let s = read_bytes src in
  write_bytes dst
    (String.sub s 0 endstr ^ boundary ~layer ~datatype rect ^ String.sub s endstr (String.length s - endstr))

(* Exchange the positions (XY records) of two TEXT elements: two pin labels
   trade places, which to an extractor that takes pins from labels is the
   same as the wires to the two pins being crossed. *)
let swap_text_xy ~src ~dst ~(a : Gds.elem) ~(b : Gds.elem) =
  let s = Bytes.of_string (read_bytes src) in
  let xy_payload (e : Gds.elem) =
    if e.ekind <> `text then invalid_arg "swap_text_xy: not a TEXT element";
    let rec scan off =
      if off >= e.eend then failwith "swap_text_xy: no XY record"
      else
        let len = (Char.code (Bytes.get s off) lsl 8) lor Char.code (Bytes.get s (off + 1)) in
        if Bytes.get s (off + 2) = '\x10' && len = 12 then off + 4 else scan (off + len) in
    scan e.estart in
  let pa = xy_payload a and pb = xy_payload b in
  let ta = Bytes.sub s pa 8 in
  Bytes.blit s pb s pa 8;
  Bytes.blit ta 0 s pb 8;
  write_bytes dst (Bytes.to_string s)
