(** Persistent verification status tracking using SQLite *)

type db_handle = Sqlite3.db

type verification_status =
  | Pass
  | Fail
  | Unknown
  | Stale

type function_record = {
  sym : string;
  name : string;
  file_path : string;
  line_number : int option;
  content_hash : string;
  spec_hash : string;
  last_verified_at : float option;
  status : verification_status;
  verification_time_ms : int option;
  error_message : string option;
  consistency_checked : bool;
  consistency_status : verification_status option;
}

(** Open or create the database *)
val open_db : string -> db_handle

(** Initialize schema if not exists *)
val init_schema : db_handle -> unit

(** Record successful verification *)
val record_function_verified :
  db_handle ->
  sym:string ->
  name:string ->
  file_path:string ->
  content_hash:string ->
  spec_hash:string ->
  time_ms:int ->
  unit

(** Record verification failure *)
val record_function_failed :
  db_handle ->
  sym:string ->
  content_hash:string ->
  spec_hash:string ->
  error:string ->
  unit

(** Get verification status for a function *)
val get_function_status : db_handle -> string -> function_record option

(** Record function -> function call dependency *)
val record_call_dependency :
  db_handle ->
  caller:string ->
  callee:string ->
  unit

(** Record function -> predicate usage *)
val record_predicate_usage :
  db_handle ->
  function_sym:string ->
  predicate_sym:string ->
  unit

(** Check if dependencies changed (hybrid policy: specs for calls, full for predicates) *)
val check_dependencies_changed :
  db_handle ->
  string ->
  (string, string * string) Hashtbl.t ->
  bool

(** Find all stale functions (content hash changed) *)
val find_stale_functions :
  db_handle ->
  (string, string * string) Hashtbl.t ->
  string list

(** Find functions needing reverification (dependency changed transitively) *)
val find_dependent_functions :
  db_handle ->
  (string, string * string) Hashtbl.t ->
  string list

(** Clear all verification data (fresh run) *)
val clear_all : db_handle -> unit

(** Close database *)
val close_db : db_handle -> bool
