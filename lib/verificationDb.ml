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


type function_record =
  { sym : string; (* Sym.pp_string *)
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
let open_db (path : string) : db_handle =
  try db_open path with
  | Error msg -> failwith (Printf.sprintf "Failed to open database %s: %s" path msg)


(** Initialize schema if not exists *)
let init_schema (db : db_handle) : unit =
  (* Set busy timeout for concurrent access FIRST *)
  (match exec db "PRAGMA busy_timeout = 5000" with
   | Rc.OK -> ()
   | rc -> failwith (Printf.sprintf "Failed to set busy timeout: %s" (Rc.to_string rc)));
  let schema =
    [ {|CREATE TABLE IF NOT EXISTS schema_version (
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
      {|CREATE TABLE IF NOT EXISTS function_uses_struct (
        function_sym TEXT NOT NULL,
        struct_name TEXT NOT NULL,
        PRIMARY KEY (function_sym, struct_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS function_uses_datatype (
        function_sym TEXT NOT NULL,
        datatype_name TEXT NOT NULL,
        PRIMARY KEY (function_sym, datatype_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS predicate_uses_predicate (
        user_sym TEXT NOT NULL,
        used_sym TEXT NOT NULL,
        PRIMARY KEY (user_sym, used_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS logical_function_uses_logical_function (
        user_sym TEXT NOT NULL,
        used_sym TEXT NOT NULL,
        PRIMARY KEY (user_sym, used_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS function_uses_logical_function (
        function_sym TEXT NOT NULL,
        logical_function_sym TEXT NOT NULL,
        PRIMARY KEY (function_sym, logical_function_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS predicate_uses_logical_function (
        predicate_sym TEXT NOT NULL,
        logical_function_sym TEXT NOT NULL,
        PRIMARY KEY (predicate_sym, logical_function_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS predicate_uses_struct (
        predicate_sym TEXT NOT NULL,
        struct_name TEXT NOT NULL,
        PRIMARY KEY (predicate_sym, struct_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS predicate_uses_datatype (
        predicate_sym TEXT NOT NULL,
        datatype_name TEXT NOT NULL,
        PRIMARY KEY (predicate_sym, datatype_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS logical_function_uses_struct (
        logical_function_sym TEXT NOT NULL,
        struct_name TEXT NOT NULL,
        PRIMARY KEY (logical_function_sym, struct_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS logical_function_uses_datatype (
        logical_function_sym TEXT NOT NULL,
        datatype_name TEXT NOT NULL,
        PRIMARY KEY (logical_function_sym, datatype_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS lemmata (
        sym TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        last_verified_at REAL,
        verification_status TEXT
      )|};
      {|CREATE TABLE IF NOT EXISTS function_uses_lemma (
        function_sym TEXT NOT NULL,
        lemma_sym TEXT NOT NULL,
        PRIMARY KEY (function_sym, lemma_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS lemma_uses_predicate (
        lemma_sym TEXT NOT NULL,
        predicate_sym TEXT NOT NULL,
        PRIMARY KEY (lemma_sym, predicate_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS lemma_uses_logical_function (
        lemma_sym TEXT NOT NULL,
        logical_function_sym TEXT NOT NULL,
        PRIMARY KEY (lemma_sym, logical_function_sym)
      )|};
      {|CREATE TABLE IF NOT EXISTS lemma_uses_struct (
        lemma_sym TEXT NOT NULL,
        struct_name TEXT NOT NULL,
        PRIMARY KEY (lemma_sym, struct_name)
      )|};
      {|CREATE TABLE IF NOT EXISTS lemma_uses_datatype (
        lemma_sym TEXT NOT NULL,
        datatype_name TEXT NOT NULL,
        PRIMARY KEY (lemma_sym, datatype_name)
      )|};
      {|CREATE INDEX IF NOT EXISTS idx_functions_status
       ON functions(verification_status)|};
      {|CREATE INDEX IF NOT EXISTS idx_functions_content_hash
       ON functions(content_hash)|}
    ]
  in
  (* Use a transaction to ensure atomicity *)
  (match exec db "BEGIN IMMEDIATE" with
   | Rc.OK -> ()
   | Rc.BUSY ->
     (* Another process is initializing, wait and retry *)
     Unix.sleepf 0.1;
     (match exec db "BEGIN IMMEDIATE" with
      | Rc.OK -> ()
      | rc -> failwith (Printf.sprintf "Schema init failed (BEGIN): %s" (Rc.to_string rc)))
   | rc -> failwith (Printf.sprintf "Schema init failed (BEGIN): %s" (Rc.to_string rc)));
  List.iter
    (fun sql ->
       match exec db sql with
       | Rc.OK -> ()
       | rc ->
         ignore (exec db "ROLLBACK");
         failwith (Printf.sprintf "Schema init failed: %s\nSQL: %s" (Rc.to_string rc) sql))
    schema;
  (* Insert or update schema version *)
  ignore (exec db "INSERT OR REPLACE INTO schema_version (version) VALUES (1)");
  (* Commit the transaction *)
  match exec db "COMMIT" with
  | Rc.OK -> ()
  | rc -> failwith (Printf.sprintf "Schema init failed (COMMIT): %s" (Rc.to_string rc))


(** Execute a prepared statement with parameters *)
let exec_stmt (stmt : stmt) (params : Data.t list) : unit =
  List.iteri (fun i param -> ignore (bind stmt (i + 1) param)) params;
  match step stmt with
  | Rc.DONE -> reset stmt |> ignore
  | rc ->
    reset stmt |> ignore;
    failwith (Printf.sprintf "Statement execution failed: %s" (Rc.to_string rc))


(** Query with a single result row *)
let query_single (db : db_handle) (sql : string) (params : Data.t list)
  : Data.t array option
  =
  try
    let stmt = prepare db sql in
    List.iteri (fun i param -> ignore (bind stmt (i + 1) param)) params;
    match step stmt with
    | Rc.ROW ->
      let row = Array.init (data_count stmt) (fun i -> column stmt i) in
      ignore (finalize stmt);
      Some row
    | _ ->
      ignore (finalize stmt);
      None
  with
  | _ -> None


(** Query multiple rows *)
let query (db : db_handle) (sql : string) (params : Data.t list) : Data.t array list =
  try
    let stmt = prepare db sql in
    List.iteri (fun i param -> ignore (bind stmt (i + 1) param)) params;
    let rec collect_rows acc =
      match step stmt with
      | Rc.ROW ->
        let row = Array.init (data_count stmt) (fun i -> column stmt i) in
        collect_rows (row :: acc)
      | _ -> List.rev acc
    in
    let rows = collect_rows [] in
    ignore (finalize stmt);
    rows
  with
  | _ -> []


(** Record successful verification of a function *)
let record_function_verified
      (db : db_handle)
      ~(sym : string)
      ~(name : string)
      ~(file_path : string)
      ~(content_hash : string)
      ~(spec_hash : string)
      ~(time_ms : int)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO functions
      (sym, name, file_path, content_hash, spec_hash,
       last_verified_at, verification_status, verification_time_ms,
       consistency_checked)
    VALUES (?, ?, ?, ?, ?, ?, 'pass', ?, 0)
  |}
  in
  try
    let stmt = prepare db sql in
    let now = Unix.time () in
    exec_stmt
      stmt
      [ Data.TEXT sym;
        Data.TEXT name;
        Data.TEXT file_path;
        Data.TEXT content_hash;
        Data.TEXT spec_hash;
        Data.FLOAT now;
        Data.INT (Int64.of_int time_ms)
      ];
    ignore (finalize stmt)
  with
  | exn ->
    failwith
      (Printf.sprintf "Failed to record function verified: %s" (Printexc.to_string exn))


(** Record verification failure *)
let record_function_failed
      (db : db_handle)
      ~(sym : string)
      ~(name : string)
      ~(file_path : string)
      ~(content_hash : string)
      ~(spec_hash : string)
      ~(error : string)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO functions
      (sym, name, file_path, content_hash, spec_hash,
       last_verified_at, verification_status, error_message,
       consistency_checked)
    VALUES (?, ?, ?, ?, ?, ?, 'fail', ?, 0)
  |}
  in
  try
    let stmt = prepare db sql in
    let now = Unix.time () in
    exec_stmt
      stmt
      [ Data.TEXT sym;
        Data.TEXT name;
        Data.TEXT file_path;
        Data.TEXT content_hash;
        Data.TEXT spec_hash;
        Data.FLOAT now;
        Data.TEXT error
      ];
    ignore (finalize stmt)
  with
  | exn ->
    failwith
      (Printf.sprintf "Failed to record function failed: %s" (Printexc.to_string exn))


(** Get verification status for a function *)
let get_function_status (db : db_handle) (sym : string) : function_record option =
  let sql =
    {|
    SELECT sym, name, file_path, line_number, content_hash, spec_hash,
           last_verified_at, verification_status, verification_time_ms,
           error_message, consistency_checked, consistency_status
    FROM functions WHERE sym = ?
  |}
  in
  match query_single db sql [ Data.TEXT sym ] with
  | None -> None
  | Some row ->
    let get_text i = match row.(i) with Data.TEXT s -> s | _ -> "" in
    let get_int_opt i =
      match row.(i) with Data.INT n -> Some (Int64.to_int n) | _ -> None
    in
    let get_float_opt i = match row.(i) with Data.FLOAT f -> Some f | _ -> None in
    Some
      { sym = get_text 0;
        name = get_text 1;
        file_path = get_text 2;
        line_number = get_int_opt 3;
        content_hash = get_text 4;
        spec_hash = get_text 5;
        last_verified_at = get_float_opt 6;
        status = status_of_string (get_text 7);
        verification_time_ms = get_int_opt 8;
        error_message = (match row.(9) with Data.TEXT s -> Some s | _ -> None);
        consistency_checked =
          (match row.(10) with Data.INT n -> Int64.compare n 0L <> 0 | _ -> false);
        consistency_status =
          (match row.(11) with Data.TEXT s -> Some (status_of_string s) | _ -> None)
      }


(** Record predicate verification *)
let record_predicate_verified
      (db : db_handle)
      ~(sym : string)
      ~(name : string)
      ~(content_hash : string)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO predicates
      (sym, name, file_path, line_number, content_hash, last_verified_at,
       verification_status, verification_time_ms, error_message,
       consistency_checked, consistency_status)
    VALUES (?, ?, '', NULL, ?, ?, 'pass', NULL, NULL, 0, NULL)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt
      stmt
      [ Data.TEXT sym; Data.TEXT name; Data.TEXT content_hash; Data.FLOAT (Unix.time ()) ];
    ignore (finalize stmt)
  with
  | exn ->
    Printf.eprintf
      "Warning: %s\n%!"
      (Printf.sprintf "Failed to record predicate verified: %s" (Printexc.to_string exn))


(** Record logical function verification *)
let record_logical_function_verified
      (db : db_handle)
      ~(sym : string)
      ~(name : string)
      ~(content_hash : string)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO logical_functions
      (sym, name, file_path, line_number, content_hash, last_verified_at,
       verification_status, verification_time_ms, error_message)
    VALUES (?, ?, '', NULL, ?, ?, 'pass', NULL, NULL)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt
      stmt
      [ Data.TEXT sym; Data.TEXT name; Data.TEXT content_hash; Data.FLOAT (Unix.time ()) ];
    ignore (finalize stmt)
  with
  | exn ->
    Printf.eprintf
      "Warning: %s\n%!"
      (Printf.sprintf
         "Failed to record logical function verified: %s"
         (Printexc.to_string exn))


(** Get predicate status *)
let get_predicate_status (db : db_handle) (sym : string) : function_record option =
  let sql =
    {|
    SELECT sym, name, content_hash FROM predicates WHERE sym = ?
  |}
  in
  match query_single db sql [ Data.TEXT sym ] with
  | None -> None
  | Some row ->
    let get_text i = match row.(i) with Data.TEXT s -> s | _ -> "" in
    Some
      { sym = get_text 0;
        name = get_text 1;
        file_path = "";
        line_number = None;
        content_hash = get_text 2;
        spec_hash = get_text 2;
        last_verified_at = None;
        status = Pass;
        verification_time_ms = None;
        error_message = None;
        consistency_checked = false;
        consistency_status = None
      }


(** Get logical function status *)
let get_logical_function_status (db : db_handle) (sym : string) : function_record option =
  let sql =
    {|
    SELECT sym, name, content_hash FROM logical_functions WHERE sym = ?
  |}
  in
  match query_single db sql [ Data.TEXT sym ] with
  | None -> None
  | Some row ->
    let get_text i = match row.(i) with Data.TEXT s -> s | _ -> "" in
    Some
      { sym = get_text 0;
        name = get_text 1;
        file_path = "";
        line_number = None;
        content_hash = get_text 2;
        spec_hash = get_text 2;
        last_verified_at = None;
        status = Pass;
        verification_time_ms = None;
        error_message = None;
        consistency_checked = false;
        consistency_status = None
      }


(** Record function -> function call dependency *)
let record_call_dependency (db : db_handle) ~(caller : string) ~(callee : string) : unit =
  let sql =
    {|
    INSERT OR IGNORE INTO function_calls_function (caller_sym, callee_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT caller; Data.TEXT callee ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Record function -> predicate usage *)
let record_predicate_usage
      (db : db_handle)
      ~(function_sym : string)
      ~(predicate_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO function_uses_predicate (function_sym, predicate_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT function_sym; Data.TEXT predicate_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get predicate dependencies for a function *)
let get_predicate_dependencies (db : db_handle) (function_sym : string) : string list =
  let sql =
    {|
    SELECT predicate_sym FROM function_uses_predicate WHERE function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Get function call dependencies for a function *)
let get_call_dependencies (db : db_handle) (caller_sym : string) : string list =
  let sql =
    {|
    SELECT callee_sym FROM function_calls_function WHERE caller_sym = ?
  |}
  in
  match query db sql [ Data.TEXT caller_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record struct definition *)
let record_struct_definition (db : db_handle) ~(name : string) ~(content_hash : string)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO struct_definitions (name, content_hash, file_path, line_number)
    VALUES (?, ?, '', NULL)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT name; Data.TEXT content_hash ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Record datatype definition *)
let record_datatype_definition (db : db_handle) ~(name : string) ~(content_hash : string)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO datatype_definitions (name, content_hash, file_path, line_number)
    VALUES (?, ?, '', NULL)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT name; Data.TEXT content_hash ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get struct definition status *)
let get_struct_definition (db : db_handle) (name : string) : function_record option =
  let sql =
    {|
    SELECT name, content_hash FROM struct_definitions WHERE name = ?
  |}
  in
  match query_single db sql [ Data.TEXT name ] with
  | None -> None
  | Some row ->
    let get_text i = match row.(i) with Data.TEXT s -> s | _ -> "" in
    Some
      { sym = get_text 0;
        name = get_text 0;
        file_path = "";
        line_number = None;
        content_hash = get_text 1;
        spec_hash = get_text 1;
        last_verified_at = None;
        status = Pass;
        verification_time_ms = None;
        error_message = None;
        consistency_checked = false;
        consistency_status = None
      }


(** Get datatype definition status *)
let get_datatype_definition (db : db_handle) (name : string) : function_record option =
  let sql =
    {|
    SELECT name, content_hash FROM datatype_definitions WHERE name = ?
  |}
  in
  match query_single db sql [ Data.TEXT name ] with
  | None -> None
  | Some row ->
    let get_text i = match row.(i) with Data.TEXT s -> s | _ -> "" in
    Some
      { sym = get_text 0;
        name = get_text 0;
        file_path = "";
        line_number = None;
        content_hash = get_text 1;
        spec_hash = get_text 1;
        last_verified_at = None;
        status = Pass;
        verification_time_ms = None;
        error_message = None;
        consistency_checked = false;
        consistency_status = None
      }


(** Record function -> struct usage *)
let record_struct_usage (db : db_handle) ~(function_sym : string) ~(struct_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO function_uses_struct (function_sym, struct_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT function_sym; Data.TEXT struct_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Record function -> datatype usage *)
let record_datatype_usage
      (db : db_handle)
      ~(function_sym : string)
      ~(datatype_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO function_uses_datatype (function_sym, datatype_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT function_sym; Data.TEXT datatype_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get struct dependencies for a function *)
let get_struct_dependencies (db : db_handle) (function_sym : string) : string list =
  let sql =
    {|
    SELECT struct_name FROM function_uses_struct WHERE function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Get datatype dependencies for a function *)
let get_datatype_dependencies (db : db_handle) (function_sym : string) : string list =
  let sql =
    {|
    SELECT datatype_name FROM function_uses_datatype WHERE function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record predicate -> predicate usage *)
let record_predicate_predicate_usage
      (db : db_handle)
      ~(user_sym : string)
      ~(used_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO predicate_uses_predicate (user_sym, used_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT user_sym; Data.TEXT used_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get predicate dependencies for a predicate *)
let get_predicate_predicate_dependencies (db : db_handle) (predicate_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT used_sym FROM predicate_uses_predicate WHERE user_sym = ?
  |}
  in
  match query db sql [ Data.TEXT predicate_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record function -> logical function usage *)
let record_function_logical_function_usage
      (db : db_handle)
      ~(function_sym : string)
      ~(logical_function_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO function_uses_logical_function (function_sym, logical_function_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT function_sym; Data.TEXT logical_function_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get logical function dependencies for a function *)
let get_function_logical_function_dependencies (db : db_handle) (function_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT logical_function_sym FROM function_uses_logical_function WHERE function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record logical function -> logical function usage *)
let record_logical_function_usage
      (db : db_handle)
      ~(user_sym : string)
      ~(used_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO logical_function_uses_logical_function (user_sym, used_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT user_sym; Data.TEXT used_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get logical function dependencies for a logical function *)
let get_logical_function_dependencies (db : db_handle) (lf_sym : string) : string list =
  let sql =
    {|
    SELECT used_sym FROM logical_function_uses_logical_function WHERE user_sym = ?
  |}
  in
  match query db sql [ Data.TEXT lf_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record predicate -> logical function usage *)
let record_predicate_logical_function_usage
      (db : db_handle)
      ~(predicate_sym : string)
      ~(logical_function_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO predicate_uses_logical_function (predicate_sym, logical_function_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT predicate_sym; Data.TEXT logical_function_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get logical function dependencies for a predicate *)
let get_predicate_logical_function_dependencies (db : db_handle) (predicate_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT logical_function_sym FROM predicate_uses_logical_function WHERE predicate_sym = ?
  |}
  in
  match query db sql [ Data.TEXT predicate_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record predicate -> struct usage *)
let record_predicate_struct_usage
      (db : db_handle)
      ~(predicate_sym : string)
      ~(struct_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO predicate_uses_struct (predicate_sym, struct_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT predicate_sym; Data.TEXT struct_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get struct dependencies for a predicate *)
let get_predicate_struct_dependencies (db : db_handle) (predicate_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT struct_name FROM predicate_uses_struct WHERE predicate_sym = ?
  |}
  in
  match query db sql [ Data.TEXT predicate_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record predicate -> datatype usage *)
let record_predicate_datatype_usage
      (db : db_handle)
      ~(predicate_sym : string)
      ~(datatype_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO predicate_uses_datatype (predicate_sym, datatype_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT predicate_sym; Data.TEXT datatype_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get datatype dependencies for a predicate *)
let get_predicate_datatype_dependencies (db : db_handle) (predicate_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT datatype_name FROM predicate_uses_datatype WHERE predicate_sym = ?
  |}
  in
  match query db sql [ Data.TEXT predicate_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record logical function -> struct usage *)
let record_logical_function_struct_usage
      (db : db_handle)
      ~(logical_function_sym : string)
      ~(struct_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO logical_function_uses_struct (logical_function_sym, struct_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT logical_function_sym; Data.TEXT struct_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get struct dependencies for a logical function *)
let get_logical_function_struct_dependencies
      (db : db_handle)
      (logical_function_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT struct_name FROM logical_function_uses_struct WHERE logical_function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT logical_function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record logical function -> datatype usage *)
let record_logical_function_datatype_usage
      (db : db_handle)
      ~(logical_function_sym : string)
      ~(datatype_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO logical_function_uses_datatype (logical_function_sym, datatype_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT logical_function_sym; Data.TEXT datatype_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get datatype dependencies for a logical function *)
let get_logical_function_datatype_dependencies
      (db : db_handle)
      (logical_function_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT datatype_name FROM logical_function_uses_datatype WHERE logical_function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT logical_function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record lemma verification *)
let record_lemma_verified
      (db : db_handle)
      ~(sym : string)
      ~(name : string)
      ~(content_hash : string)
  : unit
  =
  let sql =
    {|
    INSERT OR REPLACE INTO lemmata (sym, name, content_hash, last_verified_at, verification_status)
    VALUES (?, ?, ?, ?, 'pass')
  |}
  in
  let timestamp = Unix.time () in
  try
    let stmt = prepare db sql in
    exec_stmt
      stmt
      [ Data.TEXT sym; Data.TEXT name; Data.TEXT content_hash; Data.FLOAT timestamp ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get lemma status *)
let get_lemma_status (db : db_handle) (lemma_sym : string) : function_record option =
  let sql =
    {|
    SELECT sym, name, content_hash, last_verified_at, verification_status
    FROM lemmata WHERE sym = ?
  |}
  in
  match query db sql [ Data.TEXT lemma_sym ] with
  | [] -> None
  | row :: _ ->
    (match row with
     | [| Data.TEXT sym;
          Data.TEXT name;
          Data.TEXT content_hash;
          Data.FLOAT last_verified_at;
          Data.TEXT status_str
       |] ->
       Some
         { sym;
           name;
           file_path = "";
           line_number = None;
           content_hash;
           spec_hash = content_hash;
           last_verified_at = Some last_verified_at;
           status =
             (match status_str with "pass" -> Pass | "fail" -> Fail | _ -> Unknown);
           verification_time_ms = None;
           error_message = None;
           consistency_checked = false;
           consistency_status = None
         }
     | _ -> None)


(** Record function -> lemma usage *)
let record_function_lemma_usage
      (db : db_handle)
      ~(function_sym : string)
      ~(lemma_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO function_uses_lemma (function_sym, lemma_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT function_sym; Data.TEXT lemma_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get lemma dependencies for a function *)
let get_function_lemma_dependencies (db : db_handle) (function_sym : string) : string list
  =
  let sql =
    {|
    SELECT lemma_sym FROM function_uses_lemma WHERE function_sym = ?
  |}
  in
  match query db sql [ Data.TEXT function_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record lemma -> predicate usage *)
let record_lemma_predicate_usage
      (db : db_handle)
      ~(lemma_sym : string)
      ~(predicate_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO lemma_uses_predicate (lemma_sym, predicate_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT lemma_sym; Data.TEXT predicate_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get predicate dependencies for a lemma *)
let get_lemma_predicate_dependencies (db : db_handle) (lemma_sym : string) : string list =
  let sql =
    {|
    SELECT predicate_sym FROM lemma_uses_predicate WHERE lemma_sym = ?
  |}
  in
  match query db sql [ Data.TEXT lemma_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record lemma -> logical function usage *)
let record_lemma_logical_function_usage
      (db : db_handle)
      ~(lemma_sym : string)
      ~(logical_function_sym : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO lemma_uses_logical_function (lemma_sym, logical_function_sym)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT lemma_sym; Data.TEXT logical_function_sym ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get logical function dependencies for a lemma *)
let get_lemma_logical_function_dependencies (db : db_handle) (lemma_sym : string)
  : string list
  =
  let sql =
    {|
    SELECT logical_function_sym FROM lemma_uses_logical_function WHERE lemma_sym = ?
  |}
  in
  match query db sql [ Data.TEXT lemma_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record lemma -> struct usage *)
let record_lemma_struct_usage
      (db : db_handle)
      ~(lemma_sym : string)
      ~(struct_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO lemma_uses_struct (lemma_sym, struct_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT lemma_sym; Data.TEXT struct_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get struct dependencies for a lemma *)
let get_lemma_struct_dependencies (db : db_handle) (lemma_sym : string) : string list =
  let sql =
    {|
    SELECT struct_name FROM lemma_uses_struct WHERE lemma_sym = ?
  |}
  in
  match query db sql [ Data.TEXT lemma_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Record lemma -> datatype usage *)
let record_lemma_datatype_usage
      (db : db_handle)
      ~(lemma_sym : string)
      ~(datatype_name : string)
  : unit
  =
  let sql =
    {|
    INSERT OR IGNORE INTO lemma_uses_datatype (lemma_sym, datatype_name)
    VALUES (?, ?)
  |}
  in
  try
    let stmt = prepare db sql in
    exec_stmt stmt [ Data.TEXT lemma_sym; Data.TEXT datatype_name ];
    ignore (finalize stmt)
  with
  | _ -> ()


(** Get datatype dependencies for a lemma *)
let get_lemma_datatype_dependencies (db : db_handle) (lemma_sym : string) : string list =
  let sql =
    {|
    SELECT datatype_sym FROM lemma_uses_datatype WHERE lemma_sym = ?
  |}
  in
  match query db sql [ Data.TEXT lemma_sym ] with
  | [] -> []
  | rows -> List.map (fun row -> match row.(0) with Data.TEXT s -> s | _ -> "") rows


(** Check if a predicate and its transitive dependencies are up-to-date.
    Returns true if up-to-date, false if stale.
    Uses visited set to handle cycles. *)
let rec is_predicate_up_to_date
          (db : db_handle)
          (pred_sym : string)
          (current_pred_hashes : (string, string) Hashtbl.t)
          (current_lf_hashes : (string, string) Hashtbl.t)
          ~(visited : string list ref)
  : bool
  =
  (* Check for cycles *)
  let visited_list = !visited in
  let is_member = Stdlib.List.mem pred_sym visited_list in
  if is_member then
    true (* Already checking or checked, assume up-to-date *)
  else (
    visited := pred_sym :: !visited;
    (* Check if this predicate's hash matches *)
    match
      (get_predicate_status db pred_sym, Hashtbl.find_opt current_pred_hashes pred_sym)
    with
    | None, _ ->
      (* Not in database - check if it's a logical function instead *)
      (match
         ( get_logical_function_status db pred_sym,
           Hashtbl.find_opt current_lf_hashes pred_sym )
       with
       | None, _ -> false (* Not found, assume stale *)
       | _, None -> false (* Not in current hashes, assume stale *)
       | Some stored, Some current_hash ->
         if String.compare stored.content_hash current_hash <> 0 then
           false (* Logical function changed *)
         else (* Check logical function's dependencies recursively *)
           is_logical_function_up_to_date db pred_sym current_lf_hashes ~visited)
    | _, None -> false (* Not in current hashes, assume stale *)
    | Some stored, Some current_hash ->
      if String.compare stored.content_hash current_hash <> 0 then
        false (* This predicate changed *)
      else (
        (* Check this predicate's dependencies recursively *)
        let pred_deps = get_predicate_predicate_dependencies db pred_sym in
        let pred_deps_ok =
          List.for_all
            (fun dep_sym ->
               is_predicate_up_to_date
                 db
                 dep_sym
                 current_pred_hashes
                 current_lf_hashes
                 ~visited)
            pred_deps
        in
        if not pred_deps_ok then
          false
        else (
          (* Check logical function dependencies *)
          let lf_deps = get_predicate_logical_function_dependencies db pred_sym in
          let lf_deps_ok =
            List.for_all
              (fun lf_sym ->
                 is_logical_function_up_to_date db lf_sym current_lf_hashes ~visited)
              lf_deps
          in
          lf_deps_ok)))


(** Check if a logical function and its transitive dependencies are up-to-date.
    Returns true if up-to-date, false if stale.
    Uses visited set to handle cycles. *)
and is_logical_function_up_to_date
      (db : db_handle)
      (lf_sym : string)
      (current_lf_hashes : (string, string) Hashtbl.t)
      ~(visited : string list ref)
  : bool
  =
  (* Check for cycles *)
  let visited_list = !visited in
  if Stdlib.List.mem lf_sym visited_list then
    true (* Already checking or checked, assume up-to-date *)
  else (
    visited := lf_sym :: !visited;
    (* Check if this logical function's hash matches *)
    match
      (get_logical_function_status db lf_sym, Hashtbl.find_opt current_lf_hashes lf_sym)
    with
    | None, _ -> false (* Not in database, assume stale *)
    | _, None -> false (* Not in current hashes, assume stale *)
    | Some stored, Some current_hash ->
      if String.compare stored.content_hash current_hash <> 0 then
        false (* This logical function changed *)
      else (
        (* Check this logical function's dependencies recursively *)
        let deps = get_logical_function_dependencies db lf_sym in
        List.for_all
          (fun dep_sym ->
             is_logical_function_up_to_date db dep_sym current_lf_hashes ~visited)
          deps))


(** Check if a struct definition is up-to-date *)
let is_struct_up_to_date
      (db : db_handle)
      (struct_name : string)
      (current_struct_hashes : (string, string) Hashtbl.t)
  : bool
  =
  match
    ( get_struct_definition db struct_name,
      Hashtbl.find_opt current_struct_hashes struct_name )
  with
  | None, _ -> false (* Not in database, assume stale *)
  | _, None -> false (* Not in current hashes, assume stale *)
  | Some stored, Some current_hash -> String.compare stored.content_hash current_hash = 0


(** Check if a datatype definition is up-to-date *)
let is_datatype_up_to_date
      (db : db_handle)
      (datatype_name : string)
      (current_datatype_hashes : (string, string) Hashtbl.t)
  : bool
  =
  match
    ( get_datatype_definition db datatype_name,
      Hashtbl.find_opt current_datatype_hashes datatype_name )
  with
  | None, _ -> false (* Not in database, assume stale *)
  | _, None -> false (* Not in current hashes, assume stale *)
  | Some stored, Some current_hash -> String.compare stored.content_hash current_hash = 0


(** Clear all verification data *)
let clear_all (db : db_handle) : unit =
  let tables =
    [ "functions";
      "predicates";
      "logical_functions";
      "struct_definitions";
      "datatype_definitions";
      "function_calls_function";
      "function_uses_predicate"
    ]
  in
  List.iter
    (fun table ->
       let sql = Printf.sprintf "DELETE FROM %s" table in
       ignore (exec db sql))
    tables


(** Close database *)
let close_db (db : db_handle) : bool = db_close db

(** Check if dependencies changed - TODO: implement fully *)
let check_dependencies_changed
      (_db : db_handle)
      (_function_sym : string)
      (_current_hashes : (string, string * string) Hashtbl.t)
  : bool
  =
  (* For now, always return false - will implement dependency checking later *)
  false


(** Find stale functions - TODO: implement *)
let find_stale_functions
      (_db : db_handle)
      (_current_hashes : (string, string * string) Hashtbl.t)
  : string list
  =
  []


(** Find dependent functions - TODO: implement *)
let find_dependent_functions
      (_db : db_handle)
      (_current_hashes : (string, string * string) Hashtbl.t)
  : string list
  =
  []


(** List all functions with optional filters *)
let list_functions
      (db : db_handle)
      ?(file_filter : string option)
      ?(status_filter : string option)
      ()
  : function_record list
  =
  let select_cols =
    "sym, name, file_path, line_number, content_hash, spec_hash, last_verified_at, \
     verification_status, verification_time_ms, error_message, consistency_checked, \
     consistency_status"
  in
  let sql =
    match (file_filter, status_filter) with
    | None, None -> Printf.sprintf "SELECT %s FROM functions ORDER BY name" select_cols
    | Some _, None ->
      Printf.sprintf
        "SELECT %s FROM functions WHERE file_path LIKE ? ORDER BY name"
        select_cols
    | None, Some _ ->
      Printf.sprintf
        "SELECT %s FROM functions WHERE verification_status = ? ORDER BY name"
        select_cols
    | Some _, Some _ ->
      Printf.sprintf
        "SELECT %s FROM functions WHERE file_path LIKE ? AND verification_status = ? \
         ORDER BY name"
        select_cols
  in
  let params =
    match (file_filter, status_filter) with
    | None, None -> []
    | Some f, None -> [ Data.TEXT ("%" ^ f ^ "%") ]
    | None, Some s -> [ Data.TEXT s ]
    | Some f, Some s -> [ Data.TEXT ("%" ^ f ^ "%"); Data.TEXT s ]
  in
  let rows = query db sql params in
  List.map
    (fun row ->
       let sym = match row.(0) with Data.TEXT s -> s | _ -> "" in
       let name = match row.(1) with Data.TEXT s -> s | _ -> "" in
       let file_path = match row.(2) with Data.TEXT s -> s | _ -> "" in
       let line_number =
         match row.(3) with Data.INT i -> Some (Int64.to_int i) | _ -> None
       in
       let content_hash = match row.(4) with Data.TEXT s -> s | _ -> "" in
       let spec_hash = match row.(5) with Data.TEXT s -> s | _ -> "" in
       let last_verified_at = match row.(6) with Data.FLOAT f -> Some f | _ -> None in
       let verification_status =
         match row.(7) with
         | Data.TEXT "pass" -> Pass
         | Data.TEXT "fail" -> Fail
         | Data.TEXT "stale" -> Stale
         | _ -> Unknown
       in
       let verification_time_ms =
         match row.(8) with Data.INT i -> Some (Int64.to_int i) | _ -> None
       in
       let error_message = match row.(9) with Data.TEXT s -> Some s | _ -> None in
       let consistency_checked =
         match row.(10) with Data.INT i -> Int64.compare i 0L <> 0 | _ -> false
       in
       let consistency_status =
         match row.(11) with
         | Data.TEXT "pass" -> Some Pass
         | Data.TEXT "fail" -> Some Fail
         | Data.TEXT "stale" -> Some Stale
         | _ -> None
       in
       { sym;
         name;
         file_path;
         line_number;
         content_hash;
         spec_hash;
         last_verified_at;
         status = verification_status;
         verification_time_ms;
         error_message;
         consistency_checked;
         consistency_status
       })
    rows


(** Get count of entities by type *)
let get_entity_counts (db : db_handle) : int * int * int * int =
  let pred_count =
    query db "SELECT COUNT(*) FROM predicates" []
    |> List.hd
    |> (fun row -> row.(0))
    |> function Data.INT i -> Int64.to_int i | _ -> 0
  in
  let lf_count =
    query db "SELECT COUNT(*) FROM logical_functions" []
    |> List.hd
    |> (fun row -> row.(0))
    |> function Data.INT i -> Int64.to_int i | _ -> 0
  in
  let lemma_count =
    query db "SELECT COUNT(*) FROM lemmata" []
    |> List.hd
    |> (fun row -> row.(0))
    |> function Data.INT i -> Int64.to_int i | _ -> 0
  in
  let struct_count =
    query db "SELECT COUNT(*) FROM struct_definitions" []
    |> List.hd
    |> (fun row -> row.(0))
    |> function Data.INT i -> Int64.to_int i | _ -> 0
  in
  (pred_count, lf_count, lemma_count, struct_count)


(** Merge another database into this one *)
let merge_from_db (db : db_handle) (source_path : string)
  : (int * int * int * int, string) result
  =
  try
    (* Attach the source database *)
    let attach_sql = Printf.sprintf "ATTACH DATABASE '%s' AS source" source_path in
    let attach_stmt = prepare db attach_sql in
    exec_stmt attach_stmt [];
    ignore (finalize attach_stmt);
    (* Merge functions (INSERT OR REPLACE to overwrite if newer) *)
    let merge_funcs_sql =
      {|
      INSERT OR REPLACE INTO functions
      SELECT * FROM source.functions
    |}
    in
    let merge_funcs_stmt = prepare db merge_funcs_sql in
    exec_stmt merge_funcs_stmt [];
    ignore (finalize merge_funcs_stmt);
    let func_count =
      query db "SELECT COUNT(*) FROM source.functions" []
      |> List.hd
      |> (fun row -> row.(0))
      |> function Data.INT i -> Int64.to_int i | _ -> 0
    in
    (* Merge predicates *)
    let pred_stmt =
      prepare db "INSERT OR REPLACE INTO predicates SELECT * FROM source.predicates"
    in
    exec_stmt pred_stmt [];
    ignore (finalize pred_stmt);
    let pred_count =
      query db "SELECT COUNT(*) FROM source.predicates" []
      |> List.hd
      |> (fun row -> row.(0))
      |> function Data.INT i -> Int64.to_int i | _ -> 0
    in
    (* Merge logical functions *)
    let lf_stmt =
      prepare
        db
        "INSERT OR REPLACE INTO logical_functions SELECT * FROM source.logical_functions"
    in
    exec_stmt lf_stmt [];
    ignore (finalize lf_stmt);
    let lf_count =
      query db "SELECT COUNT(*) FROM source.logical_functions" []
      |> List.hd
      |> (fun row -> row.(0))
      |> function Data.INT i -> Int64.to_int i | _ -> 0
    in
    (* Merge lemmata *)
    let lemma_stmt =
      prepare db "INSERT OR REPLACE INTO lemmata SELECT * FROM source.lemmata"
    in
    exec_stmt lemma_stmt [];
    ignore (finalize lemma_stmt);
    let lemma_count =
      query db "SELECT COUNT(*) FROM source.lemmata" []
      |> List.hd
      |> (fun row -> row.(0))
      |> function Data.INT i -> Int64.to_int i | _ -> 0
    in
    (* Merge struct definitions *)
    let struct_stmt =
      prepare
        db
        "INSERT OR REPLACE INTO struct_definitions SELECT * FROM \
         source.struct_definitions"
    in
    exec_stmt struct_stmt [];
    ignore (finalize struct_stmt);
    (* Merge datatype definitions *)
    let dt_stmt =
      prepare
        db
        "INSERT OR REPLACE INTO datatype_definitions SELECT * FROM \
         source.datatype_definitions"
    in
    exec_stmt dt_stmt [];
    ignore (finalize dt_stmt);
    (* Merge all dependency tables *)
    let dep_tables =
      [ "function_calls_function";
        "function_uses_predicate";
        "function_uses_logical_function";
        "function_uses_struct";
        "function_uses_datatype";
        "function_uses_lemma";
        "predicate_uses_predicate";
        "predicate_uses_logical_function";
        "predicate_uses_struct";
        "predicate_uses_datatype";
        "logical_function_uses_logical_function";
        "logical_function_uses_struct";
        "logical_function_uses_datatype";
        "lemma_uses_predicate";
        "lemma_uses_logical_function";
        "lemma_uses_struct";
        "lemma_uses_datatype"
      ]
    in
    List.iter
      (fun table ->
         let sql =
           Printf.sprintf "INSERT OR IGNORE INTO %s SELECT * FROM source.%s" table table
         in
         let stmt = prepare db sql in
         exec_stmt stmt [];
         ignore (finalize stmt))
      dep_tables;
    (* Detach source database *)
    let detach_stmt = prepare db "DETACH DATABASE source" in
    exec_stmt detach_stmt [];
    ignore (finalize detach_stmt);
    Ok (func_count, pred_count, lf_count, lemma_count)
  with
  | exn -> Error (Printexc.to_string exn)
