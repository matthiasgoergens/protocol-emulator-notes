(* Minimal PNG writer: 8-bit RGB, zlib with stored (uncompressed) deflate blocks. *)
let crc_table =
  Array.init 256 (fun n ->
      let c = ref (Int32.of_int n) in
      for _ = 0 to 7 do
        c := if Int32.logand !c 1l <> 0l then Int32.logxor 0xEDB88320l (Int32.shift_right_logical !c 1)
             else Int32.shift_right_logical !c 1
      done;
      !c)

let crc32 s =
  let c = ref 0xFFFFFFFFl in
  String.iter (fun ch ->
      let i = Int32.to_int (Int32.logand (Int32.logxor !c (Int32.of_int (Char.code ch))) 0xFFl) in
      c := Int32.logxor crc_table.(i) (Int32.shift_right_logical !c 8)) s;
  Int32.logxor !c 0xFFFFFFFFl

let be32 b v = Buffer.add_int32_be b v

let chunk out typ data =
  let b = Buffer.create (String.length data + 12) in
  be32 b (Int32.of_int (String.length data));
  Buffer.add_string b typ; Buffer.add_string b data;
  be32 b (crc32 (typ ^ data));
  Buffer.add_buffer out b

let write file ~width ~height (pixel : int -> int -> int * int * int) =
  let raw = Buffer.create ((width * 3 + 1) * height) in
  for y = 0 to height - 1 do
    Buffer.add_char raw '\000';
    for x = 0 to width - 1 do
      let r, g, b = pixel x y in
      Buffer.add_char raw (Char.chr r); Buffer.add_char raw (Char.chr g); Buffer.add_char raw (Char.chr b)
    done
  done;
  let raw = Buffer.contents raw in
  let z = Buffer.create (String.length raw + 1024) in
  Buffer.add_string z "\x78\x01";
  let n = String.length raw in
  let pos = ref 0 in
  while !pos < n || n = 0 do
    let len = min 65535 (n - !pos) in
    let final = !pos + len >= n in
    Buffer.add_char z (if final then '\001' else '\000');
    Buffer.add_uint16_le z len; Buffer.add_uint16_le z (len lxor 0xFFFF);
    Buffer.add_string z (String.sub raw !pos len);
    pos := !pos + len;
    if n = 0 then pos := 1
  done;
  let a = ref 1 and b = ref 0 in
  String.iter (fun c -> a := (!a + Char.code c) mod 65521; b := (!b + !a) mod 65521) raw;
  be32 z (Int32.of_int ((!b lsl 16) lor !a));
  let out = Buffer.create (Buffer.length z + 100) in
  Buffer.add_string out "\x89PNG\r\n\x1a\n";
  let ihdr = Buffer.create 13 in
  be32 ihdr (Int32.of_int width); be32 ihdr (Int32.of_int height);
  Buffer.add_string ihdr "\008\002\000\000\000";
  chunk out "IHDR" (Buffer.contents ihdr);
  chunk out "IDAT" (Buffer.contents z);
  chunk out "IEND" "";
  Out_channel.with_open_bin file (fun oc -> Out_channel.output_string oc (Buffer.contents out))
