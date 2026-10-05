let () =
  let bits = List.concat_map (fun c -> Can_fw.bits_of (Char.code c) 8) (List.init 9 (fun i -> "123456789".[i])) in
  Printf.printf "can_fw.crc15 = 0x%04X, can_model.ref_crc = 0x%04X (catalogue CRC-15/CAN check = 0x059E)\n"
    (Can_fw.crc15 bits) (Can_model.ref_crc bits);
  (* the variant CRC engine: poly 0x8B32 left aligned, fed bit by bit *)
  let crc = List.fold_left (fun c b -> Isa_v.crc_step ~crc:c ~poly:0x8B32 b) 0 bits in
  Printf.printf "Isa_v engine (left aligned) = 0x%04X -> 0x%04X\n" crc (crc lsr 1)
