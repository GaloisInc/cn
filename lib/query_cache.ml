(* Query cache with persistent disk storage *)

(* In-memory cache *)
let cache : (string, [ `True | `False | `Unknown ]) Hashtbl.t = Hashtbl.create 10000

(* Track whether we've loaded the disk cache *)
let disk_cache_loaded = ref false

(* Statistics *)
let hits = ref 0

let misses = ref 0

let disk_hits = ref 0

let total_lookup_time = ref 0.0

let enabled = ref true

(* Persistent disk cache *)
let cache_dir () =
  let home = try Sys.getenv "HOME" with Not_found -> "." in
  Filename.concat home ".cache/cn/query-cache"


let ensure_cache_dir () =
  let dir = cache_dir () in
  let rec mkdir_p path =
    if not (Sys.file_exists path) then (
      mkdir_p (Filename.dirname path);
      Unix.mkdir path 0o755)
  in
  mkdir_p dir


let cache_file_path hash = Filename.concat (cache_dir ()) hash

let result_to_string = function
  | `True -> "unsat"
  | `False -> "sat"
  | `Unknown -> "unknown"


let result_from_string = function
  | "unsat" -> Some `True
  | "sat" -> Some `False
  | "unknown" -> Some `Unknown
  | _ -> None


(* Load entire disk cache into memory at startup *)
let load_disk_cache () =
  if !enabled && not !disk_cache_loaded then (
    disk_cache_loaded := true;
    let dir = cache_dir () in
    if Sys.file_exists dir then (
      try
        let files = Sys.readdir dir in
        Array.iter
          (fun hash ->
             let path = Filename.concat dir hash in
             try
               let ic = open_in path in
               let line = input_line ic in
               close_in ic;
               match result_from_string line with
               | Some result ->
                 if not (Hashtbl.mem cache hash) then (
                   Hashtbl.add cache hash result;
                   incr disk_hits)
               | None -> ()
             with
             | _ -> ())
          files
      with
      | _ -> ()))


let save_to_disk hash result =
  if !enabled then (
    try
      ensure_cache_dir ();
      let path = cache_file_path hash in
      (* Atomic write: write to temp file, then rename *)
      let temp_path = path ^ ".tmp." ^ string_of_int (Unix.getpid ()) in
      let oc = open_out temp_path in
      output_string oc (result_to_string result);
      output_char oc '\n';
      close_out oc;
      (* Atomic rename - if file already exists, it's fine, we're writing the same content *)
      try Unix.rename temp_path path with _ -> ()
    with
    | _ -> ())


(* Hash SMT commands directly - they use normalized variable names *)
let hash_smt_commands (commands : Sexplib.Sexp.t list) : string =
  let str = String.concat "\n" (List.map Sexplib.Sexp.to_string commands) in
  Digest.string str |> Digest.to_hex


(* Look up query in cache (all in memory after load) *)
let lookup_smt_commands (commands : Sexplib.Sexp.t list)
  : [> `True | `False | `Unknown ] option
  =
  if not !enabled then
    None
  else (
    let t0 = Unix.gettimeofday () in
    (* Load disk cache on first lookup *)
    if not !disk_cache_loaded then load_disk_cache ();
    let hash = hash_smt_commands commands in
    (* All queries are now in memory (both new and from disk) *)
    match Hashtbl.find_opt cache hash with
    | Some (`True as r) ->
      incr hits;
      let t1 = Unix.gettimeofday () in
      total_lookup_time := !total_lookup_time +. (t1 -. t0);
      Some r
    | Some (`False as r) ->
      incr hits;
      let t1 = Unix.gettimeofday () in
      total_lookup_time := !total_lookup_time +. (t1 -. t0);
      Some r
    | Some (`Unknown as r) ->
      incr hits;
      let t1 = Unix.gettimeofday () in
      total_lookup_time := !total_lookup_time +. (t1 -. t0);
      Some r
    | None ->
      incr misses;
      let t1 = Unix.gettimeofday () in
      total_lookup_time := !total_lookup_time +. (t1 -. t0);
      None)


(* Store query result in cache (both memory and disk) *)
let store_smt_commands
      (commands : Sexplib.Sexp.t list)
      (result : [< `True | `False | `Unknown ])
  : unit
  =
  if !enabled then (
    let hash = hash_smt_commands commands in
    Hashtbl.replace cache hash result;
    save_to_disk hash result)


(* Print cache statistics *)
let print_stats () =
  let total = !hits + !disk_hits + !misses in
  if total > 0 then (
    Printf.eprintf "\n=== Query Cache Statistics ===\n";
    Printf.eprintf "Enabled:  %b\n" !enabled;
    Printf.eprintf "Memory hits:  %6d\n" !hits;
    Printf.eprintf "Disk hits:    %6d\n" !disk_hits;
    Printf.eprintf "Misses:       %6d\n" !misses;
    Printf.eprintf "Total:        %6d\n" total;
    Printf.eprintf
      "Hit rate:     %5.1f%%\n"
      (100.0 *. float (!hits + !disk_hits) /. float total);
    Printf.eprintf "Memory cache: %d entries\n" (Hashtbl.length cache);
    Printf.eprintf "Disk cache:   %s\n" (cache_dir ());
    Printf.eprintf "Lookup time:  %.3fs\n" !total_lookup_time;
    Printf.eprintf "=============================\n")


(* Clear cache *)
let clear () =
  Hashtbl.clear cache;
  disk_cache_loaded := false;
  hits := 0;
  disk_hits := 0;
  misses := 0;
  total_lookup_time := 0.0;
  (* Clear disk cache *)
  if !enabled then (
    let dir = cache_dir () in
    if Sys.file_exists dir then (
      try
        let files = Sys.readdir dir in
        Array.iter (fun f -> try Unix.unlink (Filename.concat dir f) with _ -> ()) files
      with
      | _ -> ()))
