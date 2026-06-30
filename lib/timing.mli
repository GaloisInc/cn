(* Simple timing instrumentation for profiling CN overhead *)

(** Enable/disable timing instrumentation *)
val enabled : bool ref

(** Time a specific phase of execution *)
val time_phase : string -> (unit -> 'a) -> 'a

(** Time a monadic computation (for use with Typing monad) *)
val time_phase_m : string -> ('st -> 'a) -> 'st -> 'a

(** Print accumulated timing statistics *)
val print_stats : unit -> unit

(** Reset all timing statistics *)
val reset : unit -> unit
