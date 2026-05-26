(** Persistent verification status tracking using SQLite *)

open Sqlite3

type db_handle = Sqlite3.db

type verification_status =
  | Pass
  | Fail
  | Unknown
  | Stale

let string_of_status = function
  | Pass -> "pass"
  | Fail -> "fail"
  | Unknown -> "unknown"
  | Stale -> "stale"

let status_of_string = function
  | "pass" -> Pass
  | "fail" -> Fail
  | "unknown" -> Unknown
  | "stale" -> Stale
  | _ -> Unknown

type function_record = {
  sym : string;  (* Sym.pp_string *)
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
let open_db (path : string) : db_handle =
  try
    db_open path
  with Error msg ->
    failwith (Printf.sprintf "Failed to open database %s: %s" path msg)

(** Initialize schema if not exists *)
let init_schema (db : db_handle) : unit =
  let schema = [
    {|CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY
      )|};

    {|CREATE TABLE IF NOT EXISTS functions (
        sym TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        line_number INTEGER,
        content_hash TEXT NOT NULL,
        spec_hash TEXT NOT NULL,
        last_verified_at REAL,
        verification_status TEXT,
        verification_time_ms INTEGER,
        error_message TEXT,
        consistency_checked INTEGER,
        consistency_status TEXT
      )|};

    {|CREATE TABLE IF NOT EXISTS predicates (
        sym TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        line_number INTEGER,
        content_hash TEXT NOT NULL,
        last_verified_at REAL,
        verification_status TEXT,
        verification_time_ms INTEGER,
        error_message TEXT,
        consistency_checked INTEGER,
        consistency_status TEXT
      )|};

    {|CREATE TABLE IF NOT EXISTS logical_functions (
        sym TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        line_number INTEGER,
        content_hash TEXT NOT NULL,
        last_verified_at REAL,
        verification_status TEXT,
        verification_time_ms INTEGER,
        error_message TEXT
      )|};

    {|CREATE TABLE IF NOT EXISTS struct_definitions (
        name TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL,
        file_path TEXT NOT NULL,
        line_number INTEGER
      )|};

    {|CREATE TABLE IF NOT EXISTS datatype_definitions (
        name TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL,
        file_path TEXT NOT NULL,
        line_number INTEGER
      )|};

    {|CREATE TABLE IF NOT EXISTS function_calls_function (
        caller_sym TEXT NOT NULL,
        callee_sym TEXT NOT NULL,
        PRIMARY KEY (caller_sym, callee_sym)
      )|};

    {|CREATE TABLE IF NOT EXISTS function_uses_predicate (
        function_sym TEXT NOT NULL,
        predicate_sym TEXT NOT NULL,
        PRIMARY KEY (function_sym, predicate_sym)
      )|};

    {|CREATE INDEX IF NOT EXISTS idx_functions_status
       ON functions(verification_status)|};

    {|CREATE INDEX IF NOT EXISTS idx_functions_content_hash
       ON functions(content_hash)|};
  ] in

  (* Set busy timeout for concurrent access *)
  ignore (exec db "PRAGMA busy_timeout = 5000");

  List.iter (fun sql ->
    match exec db sql with
    | Rc.OK -> ()
    | rc -> failwith (Printf.sprintf "Schema init failed: %s\nSQL: %s"
                        (Rc.to_string rc) sql)
  ) schema;

  (* Insert or update schema version *)
  ignore (exec db "INSERT OR REPLACE INTO schema_version (version) VALUES (1)")

(** Execute a prepared statement with parameters *)
let exec_stmt (stmt : stmt) (params : Data.t list) : unit =
  List.iteri (fun i param ->
    ignore (bind stmt (i + 1) param)
  ) params;

  match step stmt with
  | Rc.DONE -> reset stmt |> ignore
  | rc ->
    reset stmt |> ignore;
    failwith (Printf.sprintf "Statement execution failed: %s" (Rc.to_string rc))

(** Query with a single result row *)
let query_single (db : db_handle) (sql : string) (params : Data.t list)
  : Data.t array option =
  try
    let stmt = prepare db sql in
    List.iteri (fun i param ->
      ignore (bind stmt (i + 1) param)
    ) params;

    match step stmt with
    | Rc.ROW ->
      let row = Array.init (data_count stmt) (fun i -> column stmt i) in
      ignore (finalize stmt);
      Some row
    | _ ->
      ignore (finalize stmt);
      None
  with _ -> None

(** Record successful verification of a function *)
let record_function_verified
    (db : db_handle)
    ~(sym : string)
    ~(name : string)
    ~(file_path : string)
    ~(content_hash : string)
    ~(spec_hash : string)
    ~(time_ms : int)
  : unit =
  let sql = {|
    INSERT OR REPLACE INTO functions
      (sym, name, file_path, content_hash, spec_hash,
       last_verified_at, verification_status, verification_time_ms,
       consistency_checked)
    VALUES (?, ?, ?, ?, ?, ?, 'pass', ?, 0)
  |} in

  try
    let stmt = prepare db sql in
    let now = Unix.time () in
    exec_stmt stmt [
      Data.TEXT sym;
      Data.TEXT name;
      Data.TEXT file_path;
      Data.TEXT content_hash;
      Data.TEXT spec_hash;
      Data.FLOAT now;
      Data.INT (Int64.of_int time_ms);
    ];
    ignore (finalize stmt)
  with exn ->
    failwith (Printf.sprintf "Failed to record function verified: %s"
                (Printexc.to_string exn))

(** Record verification failure *)
let record_function_failed
    (db : db_handle)
    ~(sym : string)
    ~(content_hash : string)
    ~(spec_hash : string)
    ~(error : string)
  : unit =
  let sql = {|
    INSERT OR REPLACE INTO functions
      (sym, name, file_path, content_hash, spec_hash,
       last_verified_at, verification_status, error_message,
       consistency_checked)
    VALUES (?, ?, ?, ?, ?, ?, 'fail', ?, 0)
  |} in

  try
    let stmt = prepare db sql in
    let now = Unix.time () in
    exec_stmt stmt [
      Data.TEXT sym;
      Data.TEXT sym;  (* name = sym for now *)
      Data.TEXT "";   (* file_path unknown on failure *)
      Data.TEXT content_hash;
      Data.TEXT spec_hash;
      Data.FLOAT now;
      Data.TEXT error;
    ];
    ignore (finalize stmt)
  with exn ->
    failwith (Printf.sprintf "Failed to record function failed: %s"
                (Printexc.to_string exn))

(** Get verification status for a function *)
let get_function_status (db : db_handle) (sym : string) : function_record option =
  let sql = {|
    SELECT sym, name, file_path, line_number, content_hash, spec_hash,
           last_verified_at, verification_status, verification_time_ms,
           error_message, consistency_checked, consistency_status
    FROM functions WHERE sym = ?
  |} in

  match query_single db sql [Data.TEXT sym] with
  | None -> None
  | Some row ->
    let get_text i = match row.(i) with Data.TEXT s -> s | _ -> "" in
    let get_int_opt i = match row.(i) with
      | Data.INT n -> Some (Int64.to_int n)
      | _ -> None in
    let get_float_opt i = match row.(i) with
      | Data.FLOAT f -> Some f
      | _ -> None in

    Some {
      sym = get_text 0;
      name = get_text 1;
      file_path = get_text 2;
      line_number = get_int_opt 3;
      content_hash = get_text 4;
      spec_hash = get_text 5;
      last_verified_at = get_float_opt 6;
      status = status_of_string (get_text 7);
      verification_time_ms = get_int_opt 8;
      error_message = (match row.(9) with Data.TEXT s -> Some s | _ -> None);
      consistency_checked = (match row.(10) with Data.INT n -> Int64.compare n 0L <> 0 | _ -> false);
      consistency_status = (match row.(11) with
        | Data.TEXT s -> Some (status_of_string s)
        | _ -> None);
    }

(** Record function -> function call dependency *)
let record_call_dependency
    (db : db_handle)
    ~(caller : string)
    ~(callee : string)
  : unit =
  let sql = {|
    INSERT OR IGNORE INTO function_calls_function (caller_sym, callee_sym)
    VALUES (?, ?)
  |} in

  try
    let stmt = prepare db sql in
    exec_stmt stmt [Data.TEXT caller; Data.TEXT callee];
    ignore (finalize stmt)
  with _ -> ()

(** Record function -> predicate usage *)
let record_predicate_usage
    (db : db_handle)
    ~(function_sym : string)
    ~(predicate_sym : string)
  : unit =
  let sql = {|
    INSERT OR IGNORE INTO function_uses_predicate (function_sym, predicate_sym)
    VALUES (?, ?)
  |} in

  try
    let stmt = prepare db sql in
    exec_stmt stmt [Data.TEXT function_sym; Data.TEXT predicate_sym];
    ignore (finalize stmt)
  with _ -> ()

(** Clear all verification data *)
let clear_all (db : db_handle) : unit =
  let tables = [
    "functions";
    "predicates";
    "logical_functions";
    "struct_definitions";
    "datatype_definitions";
    "function_calls_function";
    "function_uses_predicate";
  ] in

  List.iter (fun table ->
    let sql = Printf.sprintf "DELETE FROM %s" table in
    ignore (exec db sql)
  ) tables

(** Close database *)
let close_db (db : db_handle) : bool =
  db_close db

(** Check if dependencies changed - TODO: implement fully *)
let check_dependencies_changed
    (_db : db_handle)
    (_function_sym : string)
    (_current_hashes : (string, string * string) Hashtbl.t)
  : bool =
  (* For now, always return false - will implement dependency checking later *)
  false

(** Find stale functions - TODO: implement *)
let find_stale_functions
    (_db : db_handle)
    (_current_hashes : (string, string * string) Hashtbl.t)
  : string list =
  []

(** Find dependent functions - TODO: implement *)
let find_dependent_functions
    (_db : db_handle)
    (_current_hashes : (string, string * string) Hashtbl.t)
  : string list =
  []
