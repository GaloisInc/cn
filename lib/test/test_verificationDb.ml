open OUnit2
module VDb = Cn.VerificationDb

let test_open_and_init _ =
  let db = VDb.open_db ":memory:" in
  VDb.init_schema db;
  assert_bool "Database opened and initialized" (VDb.close_db db)


let test_record_and_retrieve _ =
  let db = VDb.open_db ":memory:" in
  VDb.init_schema db;
  VDb.record_function_verified
    db
    ~sym:"test_func"
    ~name:"test_func"
    ~file_path:"test.c"
    ~content_hash:"abc123"
    ~spec_hash:"def456"
    ~time_ms:100;
  let record = VDb.get_function_status db "test_func" in
  assert_bool "Function record retrieved" (Option.is_some record);
  (match record with
   | Some r ->
     assert_equal ~msg:"status" VDb.Pass r.status;
     assert_equal ~msg:"name" "test_func" r.name;
     assert_equal ~msg:"content_hash" "abc123" r.content_hash;
     assert_equal ~msg:"spec_hash" "def456" r.spec_hash;
     assert_equal ~msg:"time_ms" (Some 100) r.verification_time_ms
   | None -> assert_failure "No record found");
  ignore (VDb.close_db db)


let test_record_failure _ =
  let db = VDb.open_db ":memory:" in
  VDb.init_schema db;
  VDb.record_function_failed
    db
    ~sym:"failing_func"
    ~content_hash:"abc123"
    ~spec_hash:"def456"
    ~error:"Verification failed";
  let record = VDb.get_function_status db "failing_func" in
  assert_bool "Function record retrieved" (Option.is_some record);
  (match record with
   | Some r ->
     assert_equal ~msg:"status" VDb.Fail r.status;
     assert_equal ~msg:"error" (Some "Verification failed") r.error_message
   | None -> assert_failure "No record found");
  ignore (VDb.close_db db)


let test_dependencies _ =
  let db = VDb.open_db ":memory:" in
  VDb.init_schema db;
  VDb.record_call_dependency db ~caller:"caller_func" ~callee:"callee_func";
  VDb.record_predicate_usage
    db
    ~function_sym:"caller_func"
    ~predicate_sym:"some_predicate";
  (* Just verify no errors - dependency querying not yet implemented *)
  assert_bool "Dependencies recorded" true;
  ignore (VDb.close_db db)


let test_clear_all _ =
  let db = VDb.open_db ":memory:" in
  VDb.init_schema db;
  VDb.record_function_verified
    db
    ~sym:"test_func"
    ~name:"test_func"
    ~file_path:"test.c"
    ~content_hash:"abc123"
    ~spec_hash:"def456"
    ~time_ms:100;
  VDb.clear_all db;
  let record = VDb.get_function_status db "test_func" in
  assert_bool "Function record cleared" (Option.is_none record);
  ignore (VDb.close_db db)


let suite =
  "VerificationDb"
  >::: [ "test_open_and_init" >:: test_open_and_init;
         "test_record_and_retrieve" >:: test_record_and_retrieve;
         "test_record_failure" >:: test_record_failure;
         "test_dependencies" >:: test_dependencies;
         "test_clear_all" >:: test_clear_all
       ]


let () = run_test_tt_main suite
