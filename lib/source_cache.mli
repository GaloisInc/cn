(* Cache source file contents to prevent stale content in error messages
   when files are edited during verification *)

(** Store source file content in cache *)
val store : string -> string -> unit

(** Look up cached source file content *)
val lookup : string -> string option

(** Clear the cache *)
val clear : unit -> unit
