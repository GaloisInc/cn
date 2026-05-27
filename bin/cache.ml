open Cn
open Cmdliner

(** Show summary statistics from the cache *)
let show_summary db_path =
  let db_path = Common.expand_home db_path in
  if not (Sys.file_exists db_path) then
    Printf.printf "No cache found at %s\n" db_path
  else (
    let db = VerificationDb.open_db db_path in
    VerificationDb.init_schema db;
    let pred_count, lf_count, lemma_count, _struct_count =
      VerificationDb.get_entity_counts db
    in
    (* Count functions by status *)
    let functions = VerificationDb.list_functions db () in
    let total = List.length functions in
    let passed =
      List.length
        (List.filter (fun f -> f.VerificationDb.status == VerificationDb.Pass) functions)
    in
    let failed =
      List.length
        (List.filter (fun f -> f.VerificationDb.status == VerificationDb.Fail) functions)
    in
    Printf.printf "Cache: %s\n\n" db_path;
    Printf.printf "Functions:\n";
    Printf.printf "  Total: %d\n" total;
    Printf.printf "  Passed: %d\n" passed;
    Printf.printf "  Failed: %d\n" failed;
    Printf.printf "\n";
    Printf.printf "Other entities:\n";
    Printf.printf "  Predicates: %d\n" pred_count;
    Printf.printf "  Logical functions: %d\n" lf_count;
    Printf.printf "  Lemmata: %d\n" lemma_count;
    VerificationDb.close_db db |> ignore)


(** List failed functions *)
let show_failures db_path =
  let db_path = Common.expand_home db_path in
  if not (Sys.file_exists db_path) then
    Printf.printf "No cache found at %s\n" db_path
  else (
    let db = VerificationDb.open_db db_path in
    VerificationDb.init_schema db;
    let functions = VerificationDb.list_functions db ~status_filter:"fail" () in
    if List.length functions = 0 then
      Printf.printf "No failed functions in cache.\n"
    else (
      Printf.printf "Failed functions:\n\n";
      List.iter
        (fun f ->
           Printf.printf "  %s\n" f.VerificationDb.name;
           Printf.printf "    File: %s\n" f.VerificationDb.file_path;
           (match f.VerificationDb.error_message with
            | Some msg ->
              Printf.printf
                "    Error: %s\n"
                (String.sub msg 0 (min 100 (String.length msg)))
            | None -> ());
           Printf.printf "\n")
        functions);
    VerificationDb.close_db db |> ignore)


(** List functions from a specific file *)
let show_file db_path filename =
  let db_path = Common.expand_home db_path in
  if not (Sys.file_exists db_path) then
    Printf.printf "No cache found at %s\n" db_path
  else (
    let db = VerificationDb.open_db db_path in
    VerificationDb.init_schema db;
    let functions = VerificationDb.list_functions db ~file_filter:filename () in
    if List.length functions = 0 then
      Printf.printf "No functions found for file matching '%s'\n" filename
    else (
      Printf.printf "Functions in %s:\n\n" filename;
      List.iter
        (fun f ->
           let status_str =
             match f.VerificationDb.status with
             | VerificationDb.Pass -> "✓ pass"
             | VerificationDb.Fail -> "✗ fail"
             | VerificationDb.Stale -> "⚠ stale"
             | VerificationDb.Unknown -> "? unknown"
           in
           Printf.printf "  %s: %s\n" f.VerificationDb.name status_str)
        functions;
      Printf.printf "\n");
    VerificationDb.close_db db |> ignore)


(** Clear the cache *)
let clear_cache db_path force =
  let db_path = Common.expand_home db_path in
  if not (Sys.file_exists db_path) then
    Printf.printf "No cache found at %s\n" db_path
  else (
    if not force then (
      Printf.printf "Clear cache at %s? [y/N] " db_path;
      flush stdout;
      let response = read_line () in
      if not (String.equal response "y" || String.equal response "Y") then (
        Printf.printf "Cancelled.\n";
        exit 0));
    Sys.remove db_path;
    Printf.printf "Cache cleared.\n")


(* CLI commands *)
let db_path_arg =
  Arg.(
    value
    & opt string "~/.cache/cn/verification.db"
    & info [ "db-path" ] ~doc:"Path to verification database")


let summary_cmd =
  let term = Term.(const show_summary $ db_path_arg) in
  let info =
    Cmd.info
      "summary"
      ~doc:"Show cache statistics"
      ~man:
        [ `S Manpage.s_description;
          `P "Display summary statistics from the verification cache."
        ]
  in
  Cmd.v info term


let failures_cmd =
  let term = Term.(const show_failures $ db_path_arg) in
  let info =
    Cmd.info
      "failures"
      ~doc:"List failed functions"
      ~man:[ `S Manpage.s_description; `P "List all functions that failed verification." ]
  in
  Cmd.v info term


let file_cmd =
  let filename =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"FILE" ~doc:"File to query")
  in
  let term = Term.(const show_file $ db_path_arg $ filename) in
  let info =
    Cmd.info
      "file"
      ~doc:"Show functions from a file"
      ~man:
        [ `S Manpage.s_description;
          `P "List all cached functions from a specific file (substring match)."
        ]
  in
  Cmd.v info term


let clear_cmd =
  let force =
    Arg.(value & flag & info [ "force"; "f" ] ~doc:"Don't ask for confirmation")
  in
  let term = Term.(const clear_cache $ db_path_arg $ force) in
  let info =
    Cmd.info
      "clear"
      ~doc:"Clear the cache"
      ~man:[ `S Manpage.s_description; `P "Delete the verification cache database." ]
  in
  Cmd.v info term


let cache_cmd =
  let info =
    Cmd.info
      "cache"
      ~doc:"Query and manage verification cache"
      ~man:
        [ `S Manpage.s_description;
          `P "Commands for querying and managing the verification cache.";
          `S Manpage.s_commands;
          `P "summary - Show cache statistics";
          `P "failures - List failed functions";
          `P "file <name> - Show functions from a file";
          `P "clear - Clear the cache"
        ]
  in
  Cmd.group info [ summary_cmd; failures_cmd; file_cmd; clear_cmd ]
