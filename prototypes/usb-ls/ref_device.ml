(* Transaction-level reference model of the keyboard, from USB 2.0 chapters 8 and 9 and HID
   1.11: what a correct device answers to each transaction. The test host consults it to judge
   every reply of every device under test. It shares only the descriptor bytes (the device's
   specification) with the implementations. *)

type reply = Data of int * int list   (* PID, payload *) | Nak | Stall | Ack | Silent

type ep0 =
  | Idle
  | Data_in of { data : int list; pos : int; toggle : int; zlp : bool }
  | Status_in of [ `Addr of int | `Config of int | `Plain ]
  | Status_out
  | Stalled

type t = {
  mutable addr : int;
  mutable configured : bool;
  mutable ep0 : ep0;
  mutable ep1_toggle : int;
  reports : int list Queue.t;
  mutable last_in : [ `Ep0 | `Ep1 | `None ];
}

let create () = { addr = 0; configured = false; ep0 = Idle; ep1_toggle = 0; reports = Queue.create (); last_in = `None }

let reset d = d.addr <- 0; d.configured <- false; d.ep0 <- Idle; d.ep1_toggle <- 0; d.last_in <- `None

let take n l = List.filteri (fun i _ -> i < n) l
let drop n l = List.filteri (fun i _ -> i >= n) l

let setup d s =
  let b i = List.nth s i in
  let wlen = b 6 lor (b 7 lsl 8) in
  let desc =
    match b 0, b 1, b 3 with
    | 0x80, 0x06, 1 -> Some Descriptors.device
    | 0x80, 0x06, 2 -> Some Descriptors.config
    | 0x81, 0x06, 0x22 -> Some Descriptors.report
    | _ -> None in
  d.last_in <- `None;
  d.ep0 <-
    (match desc with
     | Some bytes ->
       let data = take wlen bytes in
       let zlp = List.length data < wlen && List.length data mod 8 = 0 in
       Data_in { data; pos = 0; toggle = 1; zlp }
     | None ->
       match b 0, b 1 with
       | 0x00, 0x05 -> Status_in (`Addr (b 2 land 0x7F))
       | 0x00, 0x09 -> Status_in (`Config (b 2))
       | 0x21, 0x0A -> Status_in `Plain
       | _ -> Stalled);
  Ack

let pid_of_toggle t = if t = 1 then Ls_host.pid_data1 else Ls_host.pid_data0

(* the reply to an IN token *)
let in_ d ~ep =
  match ep with
  | 0 ->
    (match d.ep0 with
     | Data_in { data; pos; toggle; _ } -> d.last_in <- `Ep0; Data (pid_of_toggle toggle, take 8 (drop pos data))
     | Status_in _ -> d.last_in <- `Ep0; Data (Ls_host.pid_data1, [])
     | Stalled -> Stall
     | Idle | Status_out -> Nak)
  | 1 ->
    if d.configured && not (Queue.is_empty d.reports) then (d.last_in <- `Ep1; Data (pid_of_toggle d.ep1_toggle, Queue.peek d.reports))
    else Nak
  | _ -> Stall

(* the host acknowledged the data the device sent for the last IN *)
let ack d =
  (match d.last_in with
   | `Ep0 ->
     (match d.ep0 with
      | Data_in r ->
        let sent = min 8 (List.length r.data - r.pos) in
        let pos = r.pos + sent in
        if pos < List.length r.data then d.ep0 <- Data_in { r with pos; toggle = 1 - r.toggle }
        else if sent = 8 && r.zlp then d.ep0 <- Data_in { r with pos; toggle = 1 - r.toggle; zlp = false }
        else d.ep0 <- Status_out
      | Status_in a ->
        (match a with `Addr n -> d.addr <- n | `Config n -> d.configured <- n <> 0; d.ep1_toggle <- 0 | `Plain -> ());
        d.ep0 <- Idle
      | _ -> ())
   | `Ep1 -> ignore (Queue.pop d.reports); d.ep1_toggle <- 1 - d.ep1_toggle
   | `None -> ());
  d.last_in <- `None

(* the reply to an OUT transaction carrying good data *)
let out d ~ep =
  d.last_in <- `None;
  match ep with
  | 0 -> (match d.ep0 with Stalled -> Stall | Status_out | Data_in _ -> d.ep0 <- Idle; Ack | _ -> Ack)
  | _ -> Stall
