(* Host-side model of 10BASE-T framing and line coding, written from the standard rather than
   from the RTL: CRC-32 (reflected 0xEDB88320, init and final complement 0xFFFFFFFF), Ethernet
   byte order (each byte LSB first on the wire), Manchester (a 1 is low then high, a 0 high then
   low), preamble 7 x 0x55 then SFD 0xD5, TP_IDL after the last bit. *)

let crc32_update crc byte =
  let c = ref (crc lxor byte) in
  for _ = 0 to 7 do c := if !c land 1 = 1 then (!c lsr 1) lxor 0xEDB88320 else !c lsr 1 done; !c
let crc32_reg bytes = List.fold_left crc32_update 0xFFFFFFFF bytes
let crc32 bytes = (lnot (crc32_reg bytes)) land 0xFFFFFFFF
let fcs_bytes bytes = let c = crc32 bytes in List.init 4 (fun i -> (c lsr (8 * i)) land 0xFF)

(* residual of the register after running over data followed by its FCS *)
let residual = crc32_reg ([ 0x31 ] @ fcs_bytes [ 0x31 ])

let ip_checksum words =
  let s = List.fold_left ( + ) 0 words in
  let s = (s land 0xFFFF) + (s lsr 16) in
  let s = (s land 0xFFFF) + (s lsr 16) in
  (lnot s) land 0xFFFF

let be16 v = [ (v lsr 8) land 0xFF; v land 0xFF ]

(* A UDP/IPv4 Ethernet frame with a text payload, headers precomputed on the host. *)
let udp_frame ~dst_mac ~src_mac ~src_ip ~dst_ip ~src_port ~dst_port ~payload =
  let udp_len = 8 + List.length payload in
  let udp = be16 src_port @ be16 dst_port @ be16 udp_len @ be16 0 @ payload in
  let ip_len = 20 + udp_len in
  let ip_no_ck = [ 0x45; 0x00 ] @ be16 ip_len @ be16 0x1234 @ [ 0x40; 0x00 ] @ [ 64; 17 ] @ [ 0; 0 ] @ src_ip @ dst_ip in
  let words = let rec go = function a :: b :: r -> ((a lsl 8) lor b) :: go r | _ -> [] in go ip_no_ck in
  let ck = ip_checksum words in
  let ip = List.filteri (fun i _ -> i < 10) ip_no_ck @ be16 ck @ src_ip @ dst_ip in
  let frame = dst_mac @ src_mac @ be16 0x0800 @ ip @ udp in
  (* pad to the 60-byte minimum before the FCS *)
  let frame = frame @ List.init (max 0 (60 - List.length frame)) (fun _ -> 0) in
  frame

let bits_of_byte x = List.init 8 (fun i -> (x lsr i) land 1)

(* differential line samples: +1 high, -1 low, 0 idle; [h] cycles per half bit *)
let manchester ~h bytes =
  let bits = List.concat_map bits_of_byte bytes in
  let sym b = if b = 1 then List.init h (fun _ -> -1) @ List.init h (fun _ -> 1) else List.init h (fun _ -> 1) @ List.init h (fun _ -> -1) in
  List.concat_map sym bits @ List.init (3 * h) (fun _ -> 1) @ List.init (10 * 2 * h) (fun _ -> 0)   (* TP_IDL then gap *)

let encode_frame ~h frame = manchester ~h (List.init 7 (fun _ -> 0x55) @ [ 0xD5 ] @ frame @ fcs_bytes frame)

(* Decode a comparator output (1 = positive) with activity flag into bits using mid-bit transition
   timing: after a mid-bit transition, transitions within 4 cycles are boundaries. *)
let decode ~h (samples : int array) =
  (* samples: +1/-1/0; comparator sees sign; activity = nonzero *)
  let n = Array.length samples in
  let bits = ref [] and i = ref 0 in
  let frames = ref [] in
  while !i < n do
    (* find activity *)
    while !i < n && samples.(!i) = 0 do incr i done;
    if !i < n then begin
      let last = ref !i and lvl = ref samples.(!i) and first = ref true and ended = ref false in
      bits := [];
      incr i;
      while not !ended do
        if !i >= n then ended := true
        else if samples.(!i) = 0 && !i - !last > 4 * h then ended := true
        else begin
          if samples.(!i) <> 0 && samples.(!i) <> !lvl then begin
            let d = !i - !last in
            if !first || d > 4 * h / 3 * 2 - 1 || d >= 2 * h - 1 then begin
              (* mid-bit transition: bit is the new level *)
              if not !first then bits := (if samples.(!i) > 0 then 1 else 0) :: !bits;
              first := false; last := !i
            end;
            lvl := samples.(!i)
          end;
          incr i
        end
      done;
      let bs = List.rev !bits in
      (* strip preamble up to SFD 0xD5 (LSB first: 1,0,1,0,1,0,1,1) *)
      let rec find = function
        | 1 :: 0 :: 1 :: 0 :: 1 :: 0 :: 1 :: 1 :: rest -> Some rest
        | _ :: rest -> find rest | [] -> None in
      (match find bs with
       | Some rest ->
         let nbytes = List.length rest / 8 in
         let bytes = List.init nbytes (fun k -> List.fold_left (fun acc j -> acc lor (List.nth rest (8 * k + j) lsl j)) 0 (List.init 8 Fun.id)) in
         frames := bytes :: !frames
       | None -> ())
    end
  done;
  List.rev !frames
