(* UART transmitter, 8N1, programmable divisor, with the FABulous user-design interface
   (clk, io_in[27:0], io_out[27:0], io_oeb[27:0]) so the same source serves as a fabric
   benchmark and as a hardened block. Behaviour matches bench/uart_tx.v. *)
open Hardcaml
open Signal

let create ~clock ~(io_in : t) =
  let spec = Reg_spec.create ~clock () in
  let rst = bit io_in 0 in
  let load = bit io_in 1 in
  let div_sel = select io_in 4 2 in
  let div = mux div_sel (List.init 8 (fun k -> of_int ~width:12 (16 lsl k))) in
  let open Always in
  let data = Variable.reg spec ~width:8 in
  let shifter = Variable.reg spec ~width:10 in
  let bits = Variable.reg spec ~width:4 in
  let cnt = Variable.reg spec ~width:12 in
  let busy = bits.value <>:. 0 in
  compile
    [ if_ rst
        [ shifter <-- of_int ~width:10 0x3FF; bits <--. 0; cnt <--. 0; data <--. 0x41 ]
        [ if_ (~:busy)
            [ when_ load
                [ shifter <-- concat_msb [ vdd; data.value; gnd ]
                ; bits <--. 10
                ; cnt <--. 0
                ; data <-- data.value +:. 1 ] ]
            [ if_ (cnt.value ==: div -:. 1)
                [ cnt <--. 0
                ; shifter <-- concat_msb [ vdd; select shifter.value 9 1 ]
                ; bits <-- bits.value -:. 1 ]
                [ cnt <-- cnt.value +:. 1 ] ] ] ];
  let io_out = concat_msb [ zero 26; busy; bit shifter.value 0 ] in
  let io_oeb = zero 28 in
  io_out, io_oeb

let circuit () =
  let clock = input "clk" 1 in
  let io_in = input "io_in" 28 in
  let io_out, io_oeb = create ~clock ~io_in in
  Circuit.create_exn ~name:"uart_tx" [ output "io_out" io_out; output "io_oeb" io_oeb ]
