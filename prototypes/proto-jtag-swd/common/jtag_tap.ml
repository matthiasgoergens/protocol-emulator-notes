(* Independent reference model of an IEEE 1149.1 (JTAG) Test Access Port
   controller, written from first principles against the IEEE 1149.1
   state-machine and shift/capture/update semantics.  Stdlib only.  See
   NOTES.txt for the precise edge conventions chosen. *)

type config = {
  ir_len : int;
  idcode : int option;
  bsr_len : int;
}

type state16 =
  | Test_Logic_Reset
  | Run_Test_Idle
  | Select_DR_Scan
  | Capture_DR
  | Shift_DR
  | Exit1_DR
  | Pause_DR
  | Exit2_DR
  | Update_DR
  | Select_IR_Scan
  | Capture_IR
  | Shift_IR
  | Exit1_IR
  | Pause_IR
  | Exit2_IR
  | Update_IR

let state_name = function
  | Test_Logic_Reset -> "Test-Logic-Reset"
  | Run_Test_Idle -> "Run-Test/Idle"
  | Select_DR_Scan -> "Select-DR-Scan"
  | Capture_DR -> "Capture-DR"
  | Shift_DR -> "Shift-DR"
  | Exit1_DR -> "Exit1-DR"
  | Pause_DR -> "Pause-DR"
  | Exit2_DR -> "Exit2-DR"
  | Update_DR -> "Update-DR"
  | Select_IR_Scan -> "Select-IR-Scan"
  | Capture_IR -> "Capture-IR"
  | Shift_IR -> "Shift-IR"
  | Exit1_IR -> "Exit1-IR"
  | Pause_IR -> "Pause-IR"
  | Exit2_IR -> "Exit2-IR"
  | Update_IR -> "Update-IR"

(* Standard IEEE 1149.1 TAP state diagram. *)
let next_state st tms =
  match st, tms with
  | Test_Logic_Reset, 0 -> Run_Test_Idle
  | Test_Logic_Reset, _ -> Test_Logic_Reset
  | Run_Test_Idle, 0 -> Run_Test_Idle
  | Run_Test_Idle, _ -> Select_DR_Scan
  | Select_DR_Scan, 0 -> Capture_DR
  | Select_DR_Scan, _ -> Select_IR_Scan
  | Capture_DR, 0 -> Shift_DR
  | Capture_DR, _ -> Exit1_DR
  | Shift_DR, 0 -> Shift_DR
  | Shift_DR, _ -> Exit1_DR
  | Exit1_DR, 0 -> Pause_DR
  | Exit1_DR, _ -> Update_DR
  | Pause_DR, 0 -> Pause_DR
  | Pause_DR, _ -> Exit2_DR
  | Exit2_DR, 0 -> Shift_DR
  | Exit2_DR, _ -> Update_DR
  | Update_DR, 0 -> Run_Test_Idle
  | Update_DR, _ -> Select_DR_Scan
  | Select_IR_Scan, 0 -> Capture_IR
  | Select_IR_Scan, _ -> Test_Logic_Reset
  | Capture_IR, 0 -> Shift_IR
  | Capture_IR, _ -> Exit1_IR
  | Shift_IR, 0 -> Shift_IR
  | Shift_IR, _ -> Exit1_IR
  | Exit1_IR, 0 -> Pause_IR
  | Exit1_IR, _ -> Update_IR
  | Pause_IR, 0 -> Pause_IR
  | Pause_IR, _ -> Exit2_IR
  | Exit2_IR, 0 -> Shift_IR
  | Exit2_IR, _ -> Update_IR
  | Update_IR, 0 -> Run_Test_Idle
  | Update_IR, _ -> Select_DR_Scan

(* Mandated fixed IR-capture pattern: the two least-significant bits must
   be "01"; higher bits are implementation defined, we choose 0. *)
let ir_capture_value = 0b01

let code_bypass (c : config) = (1 lsl c.ir_len) - 1
let code_idcode (c : config) =
  match c.idcode with None -> None | Some _ -> Some 1
let code_sample_preload (_c : config) = 2
let code_extest (_c : config) = 0

type dr_kind = Dr_bypass | Dr_idcode | Dr_bsr

type t = {
  cfg : config;
  mutable prev_tck : int option;
  mutable state : state16;
  mutable ir_shift : int;         (* IR shift register content *)
  mutable ir : int;               (* latched (updated) instruction *)
  mutable dr_shift : int;         (* currently selected DR shift register *)
  mutable dr_len : int;           (* bit width of the currently selected DR *)
  mutable dr_kind : dr_kind;
  mutable pins_in : int array;    (* boundary-scan capture inputs *)
  mutable pins_out : int array;   (* boundary-scan update (output) latch *)
  mutable tdo_active : bool;
  mutable tdo_bit : int;
  mutable last_shift : [ `None | `Dr | `Ir ];
    (* which register (if any) was captured/shifted at the rising edge we
       just processed; TDO reflects this at the FOLLOWING falling edge.
       Gating on this rather than on the (already-updated) current state
       is what lets the very last bit of a shift -- shifted on the same
       edge that also leaves Shift-DR/Shift-IR -- still reach TDO; see
       NOTES.txt. *)
  mutable errors : string list;
}

let select_dr_for_ir (cfg : config) ir =
  if cfg.idcode <> None && Some ir = code_idcode cfg then Dr_idcode, 32
  else if ir = code_extest cfg || ir = code_sample_preload cfg then
    Dr_bsr, cfg.bsr_len
  else Dr_bypass, 1

let create (cfg : config) =
  let init_ir =
    match code_idcode cfg with Some c -> c | None -> code_bypass cfg
  in
  let dr_kind, dr_len = select_dr_for_ir cfg init_ir in
  {
    cfg;
    prev_tck = None;
    state = Test_Logic_Reset;
    ir_shift = ir_capture_value;
    ir = init_ir;
    dr_shift = 0;
    dr_len;
    dr_kind;
    pins_in = Array.make (max cfg.bsr_len 1) 0;
    pins_out = Array.make (max cfg.bsr_len 1) 0;
    tdo_active = false;
    tdo_bit = 0;
    last_shift = `None;
    errors = [];
  }

let capture_value t =
  match t.dr_kind with
  | Dr_bypass -> 0
  | Dr_idcode -> (match t.cfg.idcode with Some v -> v | None -> 0)
  | Dr_bsr ->
    let v = ref 0 in
    for i = 0 to t.cfg.bsr_len - 1 do
      let bit = if i < Array.length t.pins_in then t.pins_in.(i) land 1 else 0 in
      v := !v lor (bit lsl i)
    done;
    !v

let do_rising_edge t ~tms ~tdi =
  let old_state = t.state in
  (* Actions keyed on the state we are leaving (pre-edge value),
     coincident with the state-register update at this same edge. *)
  (match old_state with
   | Capture_DR ->
     let k, l = select_dr_for_ir t.cfg t.ir in
     t.dr_kind <- k;
     t.dr_len <- l;
     t.dr_shift <- capture_value t;
     t.last_shift <- `Dr
   | Shift_DR ->
     let len = t.dr_len in
     t.dr_shift <- (t.dr_shift lsr 1) lor ((tdi land 1) lsl (len - 1));
     t.last_shift <- `Dr
   | Capture_IR ->
     t.ir_shift <- ir_capture_value;
     t.last_shift <- `Ir
   | Shift_IR ->
     let len = t.cfg.ir_len in
     t.ir_shift <- (t.ir_shift lsr 1) lor ((tdi land 1) lsl (len - 1));
     t.last_shift <- `Ir
   | Test_Logic_Reset ->
     (* Re-entering/staying in TLR forces IDCODE-or-BYPASS selection. *)
     t.ir <- (match code_idcode t.cfg with Some c -> c | None -> code_bypass t.cfg);
     let k, l = select_dr_for_ir t.cfg t.ir in
     t.dr_kind <- k; t.dr_len <- l;
     t.last_shift <- `None
   | _ -> t.last_shift <- `None);
  t.state <- next_state old_state (tms land 1)

let do_falling_edge t =
  (match t.state with
   | Update_DR ->
     (match t.dr_kind with
      | Dr_bsr ->
        for i = 0 to t.cfg.bsr_len - 1 do
          t.pins_out.(i) <- (t.dr_shift lsr i) land 1
        done
      | Dr_bypass | Dr_idcode -> ())
   | Update_IR ->
     t.ir <- t.ir_shift
   | _ -> ());
  (* TDO changes on the falling edge, reflecting whichever register was
     captured/shifted at the rising edge just gone -- not the (already
     advanced) current state, so the final bit of a shift survives the
     same-edge exit from Shift-DR/Shift-IR.  See NOTES.txt. *)
  t.tdo_active <- (t.last_shift <> `None);
  t.tdo_bit <-
    (match t.last_shift with
     | `Dr -> t.dr_shift land 1
     | `Ir -> t.ir_shift land 1
     | `None -> 0)

let step t ~tck ~tms ~tdi =
  (match t.prev_tck with
   | None -> ()
   | Some p ->
     if p = 0 && tck <> 0 then do_rising_edge t ~tms ~tdi
     else if p <> 0 && tck = 0 then do_falling_edge t
     else ());
  t.prev_tck <- Some tck

let tdo t = if t.tdo_active then Some (t.tdo_bit land 1) else None
let state t = state_name t.state
let ir t = t.ir

let set_pins_in t arr =
  if Array.length arr <> t.cfg.bsr_len then
    t.errors <-
      t.errors
      @ [
          Printf.sprintf
            "set_pins_in: expected array of length %d (bsr_len), got %d"
            t.cfg.bsr_len (Array.length arr);
        ];
  let n = min (Array.length arr) t.cfg.bsr_len in
  for i = 0 to n - 1 do
    t.pins_in.(i) <- arr.(i)
  done

let pins_out t = Array.copy t.pins_out
let errors t = t.errors
