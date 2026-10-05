(* the base ISA: 6-bit pc, quarter-clock bits *)
let translate ~addr w = Compat.of_base ~quarter:true ~pc_bits:6 ~addr w
