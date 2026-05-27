(** Persistent verification status tracking using SQLite *)

type db_handle = Sqlite3.db

type verification_status =
  | Pass
  | Fail
  | Unknown
  | Stale

type function_record =
  { sym : string;
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
    consistency_status : verification_status option
  }

(** Open or create the database *)
val open_db : string -> db_handle

(** Initialize schema if not exists *)
val init_schema : db_handle -> unit

(** Record successful verification *)
val record_function_verified
  :  db_handle ->
  sym:string ->
  name:string ->
  file_path:string ->
  content_hash:string ->
  spec_hash:string ->
  time_ms:int ->
  unit

(** Record verification failure *)
val record_function_failed
  :  db_handle ->
  sym:string ->
  content_hash:string ->
  spec_hash:string ->
  error:string ->
  unit

(** Get verification status for a function *)
val get_function_status : db_handle -> string -> function_record option

(** Record function -> function call dependency *)
val record_call_dependency : db_handle -> caller:string -> callee:string -> unit

(** Record function -> predicate usage *)
val record_predicate_usage
  :  db_handle ->
  function_sym:string ->
  predicate_sym:string ->
  unit

(** Get predicate dependencies for a function *)
val get_predicate_dependencies : db_handle -> string -> string list

(** Get function call dependencies for a function *)
val get_call_dependencies : db_handle -> string -> string list

(** Record predicate verification *)
val record_predicate_verified
  :  db_handle ->
  sym:string ->
  name:string ->
  content_hash:string ->
  unit

(** Record logical function verification *)
val record_logical_function_verified
  :  db_handle ->
  sym:string ->
  name:string ->
  content_hash:string ->
  unit

(** Get predicate status *)
val get_predicate_status : db_handle -> string -> function_record option

(** Get logical function status *)
val get_logical_function_status : db_handle -> string -> function_record option

(** Record struct definition *)
val record_struct_definition : db_handle -> name:string -> content_hash:string -> unit

(** Record datatype definition *)
val record_datatype_definition : db_handle -> name:string -> content_hash:string -> unit

(** Get struct definition status *)
val get_struct_definition : db_handle -> string -> function_record option

(** Get datatype definition status *)
val get_datatype_definition : db_handle -> string -> function_record option

(** Record function -> struct usage *)
val record_struct_usage : db_handle -> function_sym:string -> struct_name:string -> unit

(** Record function -> datatype usage *)
val record_datatype_usage
  :  db_handle ->
  function_sym:string ->
  datatype_name:string ->
  unit

(** Get struct dependencies for a function *)
val get_struct_dependencies : db_handle -> string -> string list

(** Get datatype dependencies for a function *)
val get_datatype_dependencies : db_handle -> string -> string list

(** Record predicate -> predicate usage *)
val record_predicate_predicate_usage
  :  db_handle ->
  user_sym:string ->
  used_sym:string ->
  unit

(** Get predicate dependencies for a predicate *)
val get_predicate_predicate_dependencies : db_handle -> string -> string list

(** Record function -> logical function usage *)
val record_function_logical_function_usage
  :  db_handle ->
  function_sym:string ->
  logical_function_sym:string ->
  unit

(** Get logical function dependencies for a function *)
val get_function_logical_function_dependencies : db_handle -> string -> string list

(** Record logical function -> logical function usage *)
val record_logical_function_usage
  :  db_handle ->
  user_sym:string ->
  used_sym:string ->
  unit

(** Get logical function dependencies for a logical function *)
val get_logical_function_dependencies : db_handle -> string -> string list

(** Record predicate -> logical function usage *)
val record_predicate_logical_function_usage
  :  db_handle ->
  predicate_sym:string ->
  logical_function_sym:string ->
  unit

(** Get logical function dependencies for a predicate *)
val get_predicate_logical_function_dependencies : db_handle -> string -> string list

(** Record predicate -> struct usage *)
val record_predicate_struct_usage
  :  db_handle ->
  predicate_sym:string ->
  struct_name:string ->
  unit

(** Get struct dependencies for a predicate *)
val get_predicate_struct_dependencies : db_handle -> string -> string list

(** Record predicate -> datatype usage *)
val record_predicate_datatype_usage
  :  db_handle ->
  predicate_sym:string ->
  datatype_name:string ->
  unit

(** Get datatype dependencies for a predicate *)
val get_predicate_datatype_dependencies : db_handle -> string -> string list

(** Record logical function -> struct usage *)
val record_logical_function_struct_usage
  :  db_handle ->
  logical_function_sym:string ->
  struct_name:string ->
  unit

(** Get struct dependencies for a logical function *)
val get_logical_function_struct_dependencies : db_handle -> string -> string list

(** Record logical function -> datatype usage *)
val record_logical_function_datatype_usage
  :  db_handle ->
  logical_function_sym:string ->
  datatype_name:string ->
  unit

(** Get datatype dependencies for a logical function *)
val get_logical_function_datatype_dependencies : db_handle -> string -> string list

(** Record lemma verification *)
val record_lemma_verified
  :  db_handle ->
  sym:string ->
  name:string ->
  content_hash:string ->
  unit

(** Get lemma status *)
val get_lemma_status : db_handle -> string -> function_record option

(** Record function -> lemma usage *)
val record_function_lemma_usage
  :  db_handle ->
  function_sym:string ->
  lemma_sym:string ->
  unit

(** Get lemma dependencies for a function *)
val get_function_lemma_dependencies : db_handle -> string -> string list

(** Record lemma -> predicate usage *)
val record_lemma_predicate_usage
  :  db_handle ->
  lemma_sym:string ->
  predicate_sym:string ->
  unit

(** Get predicate dependencies for a lemma *)
val get_lemma_predicate_dependencies : db_handle -> string -> string list

(** Record lemma -> logical function usage *)
val record_lemma_logical_function_usage
  :  db_handle ->
  lemma_sym:string ->
  logical_function_sym:string ->
  unit

(** Get logical function dependencies for a lemma *)
val get_lemma_logical_function_dependencies : db_handle -> string -> string list

(** Record lemma -> struct usage *)
val record_lemma_struct_usage
  :  db_handle ->
  lemma_sym:string ->
  struct_name:string ->
  unit

(** Get struct dependencies for a lemma *)
val get_lemma_struct_dependencies : db_handle -> string -> string list

(** Record lemma -> datatype usage *)
val record_lemma_datatype_usage
  :  db_handle ->
  lemma_sym:string ->
  datatype_name:string ->
  unit

(** Get datatype dependencies for a lemma *)
val get_lemma_datatype_dependencies : db_handle -> string -> string list

(** Check if a predicate and its transitive dependencies are up-to-date *)
val is_predicate_up_to_date
  :  db_handle ->
  string ->
  (string, string) Hashtbl.t ->
  (string, string) Hashtbl.t ->
  visited:string list ref ->
  bool

(** Check if a logical function and its transitive dependencies are up-to-date *)
val is_logical_function_up_to_date
  :  db_handle ->
  string ->
  (string, string) Hashtbl.t ->
  visited:string list ref ->
  bool

(** Check if a struct definition is up-to-date *)
val is_struct_up_to_date : db_handle -> string -> (string, string) Hashtbl.t -> bool

(** Check if a datatype definition is up-to-date *)
val is_datatype_up_to_date : db_handle -> string -> (string, string) Hashtbl.t -> bool

(** Check if dependencies changed (hybrid policy: specs for calls, full for predicates) *)
val check_dependencies_changed
  :  db_handle ->
  string ->
  (string, string * string) Hashtbl.t ->
  bool

(** Find all stale functions (content hash changed) *)
val find_stale_functions : db_handle -> (string, string * string) Hashtbl.t -> string list

(** Find functions needing reverification (dependency changed transitively) *)
val find_dependent_functions
  :  db_handle ->
  (string, string * string) Hashtbl.t ->
  string list

(** Clear all verification data (fresh run) *)
val clear_all : db_handle -> unit

(** Close database *)
val close_db : db_handle -> bool

(** List all functions with optional filters *)
val list_functions
  :  db_handle ->
  ?file_filter:string ->
  ?status_filter:string ->
  unit ->
  function_record list

(** Get count of entities (predicates, logical_functions, lemmata, structs) *)
val get_entity_counts : db_handle -> int * int * int * int

(** Merge another database into this one, returns (funcs, preds, lfs, lemmas) counts *)
val merge_from_db : db_handle -> string -> (int * int * int * int, string) result
