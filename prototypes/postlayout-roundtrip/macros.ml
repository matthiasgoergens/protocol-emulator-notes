(* Hard macros: IHP's SRAM macros as black boxes with known pins.

   The extractor knows a standard cell from below Metal1 up; a macro it
   treats as an opaque box.  Its pins come from the macro's own pin labels in
   the GDS (layer/25 text on a metal, as for the standard cells), checked
   against the pin rectangles of its LEF; its behaviour comes from IHP's
   functional Verilog model (libs.ref/sg13cmos5l_sram/verilog), which is the
   model prototypes/chip-top's macro check compared with the behavioural
   memory of the core (sim/macro_check.sh: 200,000 reads per macro, 0
   differences).  Its geometry is still flattened with the rest of the
   layout, so a top-level shape that touches a macro pin from outside, or
   two pins that the macro's own metal joins, shows up in the connectivity.

   Only the single-port macros RM_IHPSG13_1P_<words>x<width>_c2_bm_bist are
   modelled.  Their functional model (SRAM_1P_behavioral_bm_bist), on the
   rising edge of the selected clock:
     MEN & WEN:  memory[addr] <= (memory[addr] & ~BM) | (DIN & BM);
                 if REN, DOUT <= the same new word (write-through);
     else MEN & REN: DOUT <= memory[addr];
   with every input taken from the BIST port instead when BIST_EN is 1,
   including the clock.  The simulator here has one clock, so a macro whose
   BIST_EN is 1 at an edge does nothing on that edge and the edge is counted;
   Check requires BIST_EN and BIST_CLK on tie-low cells and A_DLY on a
   tie-high cell (the model stops the simulation if A_DLY is not 1). *)

type dir = In | Out

(* Port names and directions from a Verilog module header, one entry per bit,
   named the way layouts label them: "A_ADDR[3]".  Accepts both header
   styles: "input [8:0] A_ADDR;" (a list of declarations after the port
   names) and "input wire [7:0] ui_in, // comment" (ANSI ports). *)
let verilog_ports (path : string) : (string * dir) list =
  let ic = open_in path in
  let acc = ref [] in
  (try
     while true do
       let line = input_line ic in
       let line =
         match String.index_opt line '/' with
         | Some i when i + 1 < String.length line && line.[i + 1] = '/' -> String.sub line 0 i
         | _ -> line in
       let words =
         String.split_on_char ' ' (String.map (function '\t' | ',' | ';' -> ' ' | c -> c) line)
         |> List.filter (fun w -> w <> "" && w <> "wire" && w <> "reg") in
       let add dir width name =
         if width = 1 then acc := (name, dir) :: !acc
         else for i = 0 to width - 1 do acc := (Printf.sprintf "%s[%d]" name i, dir) :: !acc done
       in
       let width_of r = Scanf.sscanf r "[%d:%d]" (fun hi lo -> hi - lo + 1) in
       match words with
       | [ ("input" | "output") as d; r; n ] when r.[0] = '[' ->
         add (if d = "input" then In else Out) (width_of r) n
       | [ ("input" | "output") as d; n ] -> add (if d = "input" then In else Out) 1 n
       | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  List.rev !acc

let is_macro name = List.exists (Extract.starts_with name) Extract.macro_prefixes

type spec = { words : int; width : int; abits : int }

(* "RM_IHPSG13_1P_512x16_c2_bm_bist" -> 512 words of 16 bits *)
let spec_of_name name =
  (* not Scanf: its %d takes the "_" of "16_c2" as a digit separator *)
  let pre = "RM_IHPSG13_1P_" and post = "_c2_bm_bist" in
  let np = String.length pre and nq = String.length post and n = String.length name in
  if n <= np + nq || not (Extract.starts_with name pre) || String.sub name (n - nq) nq <> post then None
  else
    match String.split_on_char 'x' (String.sub name np (n - np - nq)) with
    | [ w; b ] ->
      (match int_of_string_opt w, int_of_string_opt b with
       | Some words, Some width when words > 1 && words land (words - 1) = 0 ->
         let rec log2 n = if n <= 1 then 0 else 1 + log2 (n / 2) in
         Some { words; width; abits = log2 words }
       | _ -> None)
    | _ -> None

let power_pins = Extract.power_pins

(* The functional model's Verilog for a macro, found next to the standard
   cells' models: .../libs.ref/<lib>_stdcell/verilog/<lib>_stdcell.v ->
   .../libs.ref/<lib>_sram/verilog/<macro>.v *)
let verilog_of ~models name =
  let libref = Filename.dirname (Filename.dirname (Filename.dirname models)) in
  let lib = Filename.basename (Filename.dirname (Filename.dirname models)) in
  let sram = (match String.rindex_opt lib '_' with Some i -> String.sub lib 0 i | None -> lib) ^ "_sram" in
  Filename.concat libref (Filename.concat sram (Filename.concat "verilog" (name ^ ".v")))

let lef_of ~models name =
  let v = verilog_of ~models name in
  Filename.concat (Filename.dirname (Filename.dirname v)) (Filename.concat "lef" (name ^ ".lef"))

(* A macro as a cell for Check and Sim: its pins from the Verilog header, no
   gates, no flip-flops; Sim adds the memory itself. *)
let cell_of ~models name : Cells.cell =
  let path = verilog_of ~models name in
  if not (Sys.file_exists path) then failwith ("macro " ^ name ^ ": no functional model at " ^ path);
  let ports = verilog_ports path in
  let unsupported =
    match spec_of_name name with
    | Some s when List.mem_assoc (Printf.sprintf "A_ADDR[%d]" (s.abits - 1)) ports
                  && List.mem_assoc (Printf.sprintf "A_DOUT[%d]" (s.width - 1)) ports -> None
    | Some _ -> Some "the model's ports do not match its name"
    | None -> Some "not a single-port RM_IHPSG13_1P macro"
  in
  { Cells.cname = name;
    inputs = List.filter_map (fun (p, d) -> if d = In then Some p else None) ports;
    outputs = List.filter_map (fun (p, d) -> if d = Out then Some p else None) ports;
    gates = [||]; ffs = []; unsupported }

(* Add a cell for every macro the netlist instantiates. *)
let add_to_lib ~models (lib : (string, Cells.cell) Hashtbl.t) (nl : Extract.netlist) =
  Array.iter (fun (i : Extract.inst) ->
    if is_macro i.icell && not (Hashtbl.mem lib i.icell) then
      Hashtbl.replace lib i.icell (cell_of ~models i.icell)) nl.instances

(* ---- LEF pins, to check the GDS labels against ---- *)

(* signal pins of one LEF macro: name -> rectangles (layer, x0, y0, x1, y1) in um *)
let lef_pins path =
  let ic = open_in path in
  let pins = Hashtbl.create 128 in
  let cur = ref None and layer = ref "" and use_signal = ref true in
  (try
     while true do
       match String.split_on_char ' ' (String.trim (input_line ic)) |> List.filter (( <> ) "") with
       | [ "PIN"; n ] -> cur := Some n; use_signal := true
       | [ "USE"; u; ";" ] -> use_signal := (u = "SIGNAL")
       | [ "LAYER"; l; ";" ] -> layer := l
       | [ "RECT"; x0; y0; x1; y1; ";" ] ->
         (match !cur with
          | Some n when !use_signal ->
            let f = float_of_string in
            Hashtbl.replace pins n ((!layer, f x0, f y0, f x1, f y1)
                                    :: Option.value ~default:[] (Hashtbl.find_opt pins n))
          | _ -> ())
       | [ "END"; n ] when Some n = !cur -> cur := None
       | "OBS" :: _ -> cur := None
       | _ -> ()
     done
   with End_of_file -> ());
  close_in ic;
  pins

(* Every signal pin of the LEF has exactly one GDS label of the same name on
   the same metal, inside one of its rectangles, and every GDS label is a LEF
   signal pin.  Returns the problems found (empty when they agree). *)
let check_labels_against_lef ~(lef : string) ~(gds : Gds.lib) ~(tech : Extract.tech) name =
  let pins = lef_pins lef in
  let cell = Hashtbl.find gds.cells name in
  let dbu = gds.dbu_um in
  let problems = ref [] in
  let labels =
    List.filter_map (fun (l : Gds.label) ->
      if l.ltexttype = Extract.text_datatype && Extract.metal_index tech l.llayer <> None
         && not (List.mem l.ltext power_pins)
      then Some { l with ltext = Extract.bus_name l.ltext } else None) cell.labels in
  List.iter (fun (l : Gds.label) ->
    match Hashtbl.find_opt pins l.ltext with
    | None -> problems := Printf.sprintf "%s: GDS label %s is not a LEF signal pin" name l.ltext :: !problems
    | Some rects ->
      let x = l.lx *. dbu and y = l.ly *. dbu in
      let metal = (Option.get (Extract.metal_index tech l.llayer)) in
      let mname = tech.metals.(metal).mname in
      if not (List.exists (fun (ly, x0, y0, x1, y1) -> ly = mname && x0 <= x && x <= x1 && y0 <= y && y <= y1) rects)
      then problems := Printf.sprintf "%s: label %s at (%.3f, %.3f) on %s is in none of its LEF rectangles"
                           name l.ltext x y mname :: !problems) labels;
  Hashtbl.iter (fun p _ ->
    match List.length (List.filter (fun (l : Gds.label) -> l.ltext = p) labels) with
    | 1 -> ()
    | k -> problems := Printf.sprintf "%s: LEF signal pin %s has %d GDS labels" name p k :: !problems) pins;
  (Hashtbl.length pins, List.length labels, List.rev !problems)
