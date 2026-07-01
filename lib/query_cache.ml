(* Query cache with SQLite persistent storage *)

(* Statistics *)
let hits = ref 0

let misses = ref 0

let total_lookup_time = ref 0.0

let hash_time = ref 0.0

let db_time = ref 0.0

let enabled = ref true

(* Debug flag - set via CN_QUERY_CACHE_DEBUG environment variable *)
let debug_enabled () =
  try match Sys.getenv "CN_QUERY_CACHE_DEBUG" with "1" -> true | _ -> false with
  | Not_found -> false


(* SQLite database handle *)
let db : Sqlite3.db option ref = ref None

(* Get cache database path *)
let cache_db_path () =
  let home = try Sys.getenv "HOME" with Not_found -> "." in
  let cache_dir = Filename.concat home ".cache/cn" in
  let rec mkdir_p path =
    if not (Sys.file_exists path) then (
      mkdir_p (Filename.dirname path);
      Unix.mkdir path 0o755)
  in
  mkdir_p cache_dir;
  Filename.concat cache_dir "query-cache.db"


(* Initialize SQLite database *)
let init_db () =
  match !db with
  | Some _ -> ()
  | None ->
    if !enabled then (
      try
        let path = cache_db_path () in
        let db_handle = Sqlite3.db_open path in
        (* Create table if it doesn't exist *)
        let _ =
          Sqlite3.exec
            db_handle
            "CREATE TABLE IF NOT EXISTS query_cache (hash TEXT PRIMARY KEY,result \
             INTEGER NOT NULL) WITHOUT ROWID"
        in
        (* Create index on hash for faster lookups (though PRIMARY KEY already indexes) *)
        db := Some db_handle
      with
      | _ -> ())


(* Convert result to integer for storage *)
let result_to_int = function `True -> 0 | `False -> 1 | `Unknown -> 2

(* Convert integer to result *)
let result_from_int = function
  | 0 -> Some `True
  | 1 -> Some `False
  | 2 -> Some `Unknown
  | _ -> None


(* Hash SMT commands - must use string serialization for determinism *)
let hash_smt_commands (commands : Sexplib.Sexp.t list) : string =
  let t0 = Unix.gettimeofday () in
  let num_commands = List.length commands in
  (* Convert to string and hash. String serialization is required for deterministic
     hashing across runs - structural hashing can vary with memory layout. *)
  let buf = Buffer.create 4096 in
  List.iter
    (fun cmd ->
       Sexplib.Sexp.to_buffer ~buf cmd;
       Buffer.add_char buf '\n')
    commands;
  let str = Buffer.contents buf in
  let str_len = String.length str in
  let hash = Digest.string str |> Digest.to_hex in
  let t1 = Unix.gettimeofday () in
  hash_time := !hash_time +. (t1 -. t0);
  if
    debug_enabled () && num_commands > 0 && (num_commands mod 1000 = 0 || str_len > 100000)
  then
    Printf.eprintf
      "[HASH] %d commands, %d bytes, %.3fms\n%!"
      num_commands
      str_len
      ((t1 -. t0) *. 1000.0);
  hash


(* Look up query in cache by pre-computed hash *)
let lookup_by_hash (hash : string) : [> `True | `False | `Unknown ] option =
  if not !enabled then
    None
  else (
    let t0 = Unix.gettimeofday () in
    init_db ();
    let result =
      match !db with
      | None -> None
      | Some db_handle ->
        (try
           let stmt =
             Sqlite3.prepare db_handle "SELECT result FROM query_cache WHERE hash = ?"
           in
           let _ = Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT hash) in
           match Sqlite3.step stmt with
           | Sqlite3.Rc.ROW ->
             (match Sqlite3.Data.to_int (Sqlite3.column stmt 0) with
              | Some result_int ->
                let _ = Sqlite3.finalize stmt in
                result_from_int result_int
              | None ->
                let _ = Sqlite3.finalize stmt in
                None)
           | _ ->
             let _ = Sqlite3.finalize stmt in
             None
         with
         | _ -> None)
    in
    let t1 = Unix.gettimeofday () in
    db_time := !db_time +. (t1 -. t0);
    total_lookup_time := !total_lookup_time +. (t1 -. t0);
    (match result with Some _ -> incr hits | None -> incr misses);
    result)


(* Legacy API for backward compatibility - computes hash from commands *)
let lookup_smt_commands (commands : Sexplib.Sexp.t list)
  : [> `True | `False | `Unknown ] option
  =
  if not !enabled then
    None
  else (
    let hash = hash_smt_commands commands in
    lookup_by_hash hash)


(* Store query result in cache by pre-computed hash *)
let store_by_hash (hash : string) (result : [< `True | `False | `Unknown ]) : unit =
  if !enabled then (
    init_db ();
    match !db with
    | None -> ()
    | Some db_handle ->
      (try
         let stmt =
           Sqlite3.prepare
             db_handle
             "INSERT OR REPLACE INTO query_cache (hash, result) VALUES (?, ?)"
         in
         let _ = Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT hash) in
         let _ =
           Sqlite3.bind stmt 2 (Sqlite3.Data.INT (Int64.of_int (result_to_int result)))
         in
         let _ = Sqlite3.step stmt in
         let _ = Sqlite3.finalize stmt in
         ()
       with
       | _ -> ()))


(* Legacy API for backward compatibility - computes hash from commands *)
let store_smt_commands
      (commands : Sexplib.Sexp.t list)
      (result : [< `True | `False | `Unknown ])
  : unit
  =
  if !enabled then (
    let hash = hash_smt_commands commands in
    store_by_hash hash result)


(* Print cache statistics *)
let print_stats () =
  let total = !hits + !misses in
  if total > 0 then (
    let cache_size =
      match !db with
      | None -> 0
      | Some db_handle ->
        (try
           let stmt = Sqlite3.prepare db_handle "SELECT COUNT(*) FROM query_cache" in
           match Sqlite3.step stmt with
           | Sqlite3.Rc.ROW ->
             (match Sqlite3.Data.to_int (Sqlite3.column stmt 0) with
              | Some count ->
                let _ = Sqlite3.finalize stmt in
                count
              | None ->
                let _ = Sqlite3.finalize stmt in
                0)
           | _ ->
             let _ = Sqlite3.finalize stmt in
             0
         with
         | _ -> 0)
    in
    Printf.eprintf "\n=== Query Cache Statistics ===\n";
    Printf.eprintf "Enabled:      %b\n" !enabled;
    Printf.eprintf "Hits:         %6d\n" !hits;
    Printf.eprintf "Misses:       %6d\n" !misses;
    Printf.eprintf "Total:        %6d\n" total;
    Printf.eprintf "Hit rate:     %5.1f%%\n" (100.0 *. float !hits /. float total);
    Printf.eprintf "Cache entries: %d\n" cache_size;
    Printf.eprintf "Cache db:     %s\n" (cache_db_path ());
    if debug_enabled () then (
      Printf.eprintf "Lookup time:  %.3fs\n" !total_lookup_time;
      Printf.eprintf
        "  Hash time:  %.3fs (%.1f%%)\n"
        !hash_time
        (100.0 *. !hash_time /. !total_lookup_time);
      Printf.eprintf
        "  DB time:    %.3fs (%.1f%%)\n"
        !db_time
        (100.0 *. !db_time /. !total_lookup_time));
    Printf.eprintf "=============================\n")


(* Clear cache *)
let clear () =
  hits := 0;
  misses := 0;
  total_lookup_time := 0.0;
  match !db with
  | None -> ()
  | Some db_handle ->
    (try
       let _ = Sqlite3.exec db_handle "DELETE FROM query_cache" in
       ()
     with
     | _ -> ())
