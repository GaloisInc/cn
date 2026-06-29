module CF = Cerb_frontend
module CB = Cerb_backend
open Cn

let well_formed
      filename
      cc
      macros
      permissive
      incl_dirs
      incl_files
      json
      json_trace
      output_dir
      only
      csv_times
      astprints
      no_inherit_loc
      magic_comment_char_dollar
      allow_split_magic_comments
      cache_status
      db_path
  =
  let filename = Common.there_can_only_be_one filename in
  if cache_status then (
    (* Cache status mode: parse file and check against database *)
    let db_path = Common.expand_home db_path in
    Common.with_well_formedness_check
      ~filename
      ~cc
      ~macros
      ~permissive
      ~incl_dirs
      ~incl_files
      ~coq_export_file:None
      ~coq_mucore:false
      ~coq_proof_log:false
      ~coq_check_proof_log:false
      ~csv_times
      ~astprints
      ~no_inherit_loc
      ~magic_comment_char_dollar
      ~allow_split_magic_comments
      ~save_cpp:None
      ~disable_linemarkers:false
      ~skip_label_inlining:false
      ~handle_error:(fun _ -> ())
      ~f:(fun ~cabs_tunit:_ ~prog5:_ ~ail_prog:_ ~statement_locs:_ ~paused ->
        let check (c_functions, _global_var_constraints, _lemmas) =
          let open Typing in
          if not (Sys.file_exists db_path) then (
            Printf.printf "No cache found at %s\n" db_path;
            Printf.printf "All functions would need verification (no cache).\n";
            return ())
          else (
            let db = VerificationDb.open_db db_path in
            VerificationDb.init_schema db;
            let@ global = get_global () in
            (* Filter functions based on --only flag *)
            let selected_funs =
              match only with
              | [] -> c_functions
              | names ->
                List.filter
                  (fun (fsym, _) ->
                     let sym_str = Sym.pp_string fsym in
                     List.exists (fun name -> String.equal name sym_str) names)
                  c_functions
            in
            if not json then (
              Printf.printf "Cache Status Report\n";
              Printf.printf "===================\n\n";
              Printf.printf "Database: %s\n" db_path;
              Printf.printf "File: %s\n" filename;
              Printf.printf "Functions analyzed: %d\n\n" (List.length selected_funs));
            (* Compute all current hashes like verify does - for ALL functions including trusted *)
            let current_hashes = Hashtbl.create (Sym.Map.cardinal global.fun_decls) in
            let@ () =
              let rec compute_hashes = function
                | [] -> return ()
                | (fsym, (loc, args_and_body)) :: rest ->
                  let@ _loc, ft_opt, _sig = Global.get_fun_decl loc fsym in
                  let spec_hash = ContentHash.hash_function_spec ft_opt in
                  let content_hash = ContentHash.hash_args_and_body args_and_body in
                  Hashtbl.add current_hashes (Sym.pp_string fsym) (content_hash, spec_hash);
                  compute_hashes rest
              in
              compute_hashes c_functions
            in
            (* Also add trusted functions and other functions not in c_functions *)
            Sym.Map.iter
              (fun fsym (_, ft_opt, _) ->
                 let sym_str = Sym.pp_string fsym in
                 if not (Hashtbl.mem current_hashes sym_str) then (
                   let spec_hash = ContentHash.hash_function_spec ft_opt in
                   Hashtbl.add current_hashes sym_str ("not_verified", spec_hash)))
              global.fun_decls;
            (* Compute current hashes for all predicates *)
            let current_pred_hashes =
              Hashtbl.create (Sym.Map.cardinal global.resource_predicates)
            in
            let@ () =
              Sym.Map.fold
                (fun pred_sym pred_def acc ->
                   let@ () = acc in
                   let pred_hash = ContentHash.hash_predicate pred_def in
                   Hashtbl.add current_pred_hashes (Sym.pp_string pred_sym) pred_hash;
                   return ())
                global.resource_predicates
                (return ())
            in
            (* Compute current hashes for all logical functions *)
            let current_lf_hashes =
              Hashtbl.create (Sym.Map.cardinal global.logical_functions)
            in
            let@ () =
              Sym.Map.fold
                (fun lf_sym lf_def acc ->
                   let@ () = acc in
                   let lf_hash = ContentHash.hash_logical_function lf_def in
                   Hashtbl.add current_lf_hashes (Sym.pp_string lf_sym) lf_hash;
                   return ())
                global.logical_functions
                (return ())
            in
            (* Compute current hashes for all structs and datatypes *)
            let current_struct_hashes =
              Hashtbl.create (Sym.Map.cardinal global.struct_decls)
            in
            Sym.Map.iter
              (fun struct_sym struct_decl ->
                 let struct_hash = ContentHash.hash_struct_definition struct_decl in
                 let canonical_name =
                   Check.canonical_struct_name struct_sym global.struct_decls
                 in
                 Hashtbl.add current_struct_hashes canonical_name struct_hash)
              global.struct_decls;
            let current_datatype_hashes =
              Hashtbl.create (Sym.Map.cardinal global.datatypes)
            in
            Sym.Map.iter
              (fun dt_sym dt_info ->
                 let dt_hash = ContentHash.hash_datatype_definition dt_info in
                 Hashtbl.add current_datatype_hashes (Sym.pp_string dt_sym) dt_hash)
              global.datatypes;
            (* Analyze each selected function using the same logic as verify *)
            let results =
              List.map
                (fun (sym, (loc, _args_and_body)) ->
                   let sym_str = Sym.pp_string sym in
                   let file_path =
                     Option.value (Cerb_location.get_filename loc) ~default:"<unknown>"
                   in
                   let content_hash, spec_hash = Hashtbl.find current_hashes sym_str in
                   (* Use the same staleness check as verify *)
                   match
                     Check.check_function_staleness
                       db
                       sym_str
                       content_hash
                       spec_hash
                       current_pred_hashes
                       current_lf_hashes
                       current_struct_hashes
                       current_datatype_hashes
                       current_hashes
                   with
                   | None ->
                     (* Up to date *)
                     let cached_status =
                       match VerificationDb.get_function_status db sym_str with
                       | Some record ->
                         (match record.VerificationDb.status with
                          | VerificationDb.Pass -> "pass"
                          | VerificationDb.Fail -> "fail"
                          | VerificationDb.Stale -> "stale"
                          | VerificationDb.Unknown -> "unknown")
                       | None -> "unknown"
                     in
                     `Assoc
                       [ ("function", `String sym_str);
                         ("location", `String file_path);
                         ("cache_status", `String "cached");
                         ("previous_status", `String cached_status);
                         ("action", `String "skip")
                       ]
                   | Some reasons ->
                     (* Stale - collect detailed reasons *)
                     let previous_status =
                       match VerificationDb.get_function_status db sym_str with
                       | Some record ->
                         (match record.VerificationDb.status with
                          | VerificationDb.Pass -> "pass"
                          | VerificationDb.Fail -> "fail"
                          | VerificationDb.Stale -> "stale"
                          | VerificationDb.Unknown -> "unknown")
                       | None -> "new"
                     in
                     let reason_to_json reason =
                       match reason with
                       | Check.NotInCache -> `Assoc [ ("type", `String "not_in_cache") ]
                       | Check.ContentChanged { old_hash; new_hash } ->
                         `Assoc
                           [ ("type", `String "content_changed");
                             ("old_hash", `String old_hash);
                             ("new_hash", `String new_hash)
                           ]
                       | Check.SpecChanged { old_hash; new_hash } ->
                         `Assoc
                           [ ("type", `String "spec_changed");
                             ("old_hash", `String old_hash);
                             ("new_hash", `String new_hash)
                           ]
                       | Check.PredicateChanged preds ->
                         `Assoc
                           [ ("type", `String "predicate_changed");
                             ("predicates", `List (List.map (fun p -> `String p) preds))
                           ]
                       | Check.StructChanged structs ->
                         `Assoc
                           [ ("type", `String "struct_changed");
                             ("structs", `List (List.map (fun s -> `String s) structs))
                           ]
                       | Check.DatatypeChanged datatypes ->
                         `Assoc
                           [ ("type", `String "datatype_changed");
                             ("datatypes", `List (List.map (fun d -> `String d) datatypes))
                           ]
                       | Check.CalleeSpecChanged callees ->
                         `Assoc
                           [ ("type", `String "callee_spec_changed");
                             ("callees", `List (List.map (fun c -> `String c) callees))
                           ]
                       | Check.LogicalFunctionChanged lfs ->
                         `Assoc
                           [ ("type", `String "logical_function_changed");
                             ( "logical_functions",
                               `List (List.map (fun lf -> `String lf) lfs) )
                           ]
                     in
                     `Assoc
                       [ ("function", `String sym_str);
                         ("location", `String file_path);
                         ("cache_status", `String "stale");
                         ("previous_status", `String previous_status);
                         ("action", `String "reverify");
                         ("reasons", `List (List.map reason_to_json reasons))
                       ])
                selected_funs
            in
            if json then (
              let json_output =
                `Assoc
                  [ ("database", `String db_path);
                    ("file", `String filename);
                    ("functions_analyzed", `Int (List.length selected_funs));
                    ("results", `List results)
                  ]
              in
              Printf.printf "%s\n" (Yojson.Basic.pretty_to_string json_output))
            else
              List.iter
                (fun result ->
                   let open Yojson.Basic.Util in
                   let cache_status =
                     result
                     |> member "cache_status"
                     |> to_string_option
                     |> Option.value ~default:""
                   in
                   let function_name =
                     result
                     |> member "function"
                     |> to_string_option
                     |> Option.value ~default:""
                   in
                   let location =
                     result
                     |> member "location"
                     |> to_string_option
                     |> Option.value ~default:""
                   in
                   let previous_status =
                     result
                     |> member "previous_status"
                     |> to_string_option
                     |> Option.value ~default:""
                   in
                   if String.equal cache_status "cached" then
                     Printf.printf
                       "[CACHED] %s (%s)\n\
                       \  Location: %s\n\
                       \  Action: Will skip verification\n\n"
                       function_name
                       previous_status
                       location
                   else (
                     Printf.printf
                       "[STALE] %s (was: %s)\n  Location: %s\n  Reasons:\n"
                       function_name
                       (String.uppercase_ascii previous_status)
                       location;
                     let reasons = result |> member "reasons" |> to_list in
                     List.iter
                       (fun reason ->
                          let rtype =
                            reason
                            |> member "type"
                            |> to_string_option
                            |> Option.value ~default:""
                          in
                          match rtype with
                          | "not_in_cache" -> Printf.printf "    - Not in cache\n"
                          | "content_changed" ->
                            let old_h =
                              reason
                              |> member "old_hash"
                              |> to_string_option
                              |> Option.map (fun s ->
                                String.sub s 0 (min 8 (String.length s)))
                              |> Option.value ~default:""
                            in
                            let new_h =
                              reason
                              |> member "new_hash"
                              |> to_string_option
                              |> Option.map (fun s ->
                                String.sub s 0 (min 8 (String.length s)))
                              |> Option.value ~default:""
                            in
                            Printf.printf
                              "    - Content changed (old: %s, new: %s)\n"
                              old_h
                              new_h
                          | "spec_changed" ->
                            let old_h =
                              reason
                              |> member "old_hash"
                              |> to_string_option
                              |> Option.map (fun s ->
                                String.sub s 0 (min 8 (String.length s)))
                              |> Option.value ~default:""
                            in
                            let new_h =
                              reason
                              |> member "new_hash"
                              |> to_string_option
                              |> Option.map (fun s ->
                                String.sub s 0 (min 8 (String.length s)))
                              |> Option.value ~default:""
                            in
                            Printf.printf
                              "    - Spec changed (old: %s, new: %s)\n"
                              old_h
                              new_h
                          | "predicate_changed" ->
                            let preds =
                              reason |> member "predicates" |> to_list |> filter_string
                            in
                            Printf.printf
                              "    - Predicate dependencies changed: %s\n"
                              (String.concat ", " preds)
                          | "struct_changed" ->
                            let structs =
                              reason |> member "structs" |> to_list |> filter_string
                            in
                            Printf.printf
                              "    - Struct dependencies changed: %s\n"
                              (String.concat ", " structs)
                          | "datatype_changed" ->
                            let datatypes =
                              reason |> member "datatypes" |> to_list |> filter_string
                            in
                            Printf.printf
                              "    - Datatype dependencies changed: %s\n"
                              (String.concat ", " datatypes)
                          | "callee_spec_changed" ->
                            let callees =
                              reason |> member "callees" |> to_list |> filter_string
                            in
                            Printf.printf
                              "    - Called function specs changed: %s\n"
                              (String.concat ", " callees)
                          | "logical_function_changed" ->
                            let lfs =
                              reason
                              |> member "logical_functions"
                              |> to_list
                              |> filter_string
                            in
                            Printf.printf
                              "    - Logical function dependencies changed: %s\n"
                              (String.concat ", " lfs)
                          | _ -> ())
                       reasons;
                     Printf.printf "  Action: Will re-verify\n\n"))
                results;
            VerificationDb.close_db db |> ignore;
            return ())
        in
        Typing.run_from_pause check paused))
  else (* Normal well-formedness check *)
    Common.with_well_formedness_check
      ~filename
      ~cc
      ~macros
      ~permissive
      ~incl_dirs
      ~incl_files
      ~coq_export_file:None
      ~coq_mucore:false
      ~coq_proof_log:false
      ~coq_check_proof_log:false
      ~csv_times
      ~astprints
      ~no_inherit_loc
      ~magic_comment_char_dollar
      ~allow_split_magic_comments
      ~save_cpp:None
      ~disable_linemarkers:false
      ~skip_label_inlining:false
      ~handle_error:
        (Common.handle_type_error ~json ?output_dir ~serialize_json:json_trace)
      ~f:(fun ~cabs_tunit:_ ~prog5:_ ~ail_prog:_ ~statement_locs:_ ~paused:_ ->
        Or_TypeError.return ())


open Cmdliner

let cmd =
  let open Term in
  let only_flag =
    let doc = "Only analyze this function (or comma-separated names) for cache status" in
    Arg.(value & opt (list string) [] & info [ "only" ] ~doc)
  in
  let cache_status_flag =
    Arg.(
      value
      & flag
      & info
          [ "cache-status" ]
          ~doc:
            "Parse file and show cache status (which functions would be verified vs \
             cached)")
  in
  let db_path_flag =
    Arg.(
      value
      & opt string ".cn/verification.db"
      & info [ "db-path" ] ~doc:"Path to verification database (for --cache-status)")
  in
  let wf_t =
    const well_formed
    $ Common.Flags.file
    $ Common.Flags.cc
    $ Common.Flags.macros
    $ Common.Flags.permissive
    $ Common.Flags.incl_dirs
    $ Common.Flags.incl_files
    $ Verify.Flags.json
    $ Verify.Flags.json_trace
    $ Verify.Flags.output_dir
    $ only_flag
    $ Common.Flags.csv_times
    $ Common.Flags.astprints
    $ Common.Flags.no_inherit_loc
    $ Common.Flags.magic_comment_char_dollar
    $ Common.Flags.allow_split_magic_comments
    $ cache_status_flag
    $ db_path_flag
  in
  let doc =
    "Runs CN's well-formedness check\n\
    \    which finds errors such as\n\
    \    ill-typing CN definitions\n\
    \    (predicates, specifications, lemmas)\n\
    \    and ill-formed recursion in datatypes.\n\
    \    It DOES NOT verify C functions,\n\
    \    which `cn verify` does.\n\n\
    \    With --cache-status, parses the file and shows\n\
    \    which functions would be verified vs cached,\n\
    \    comparing computed hashes with the database."
  in
  let info = Cmd.info "wf" ~doc in
  Cmd.v info wf_t
