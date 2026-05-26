open OUnit2

module IT = Cn.IndexTerms
module BT = Cn.BaseTypes
module CH = Cn.ContentHash
module Loc = Cn.Locations
module Sym = Cn.Sym

(* Test that alpha-renaming works: semantically equivalent terms should hash the same *)
let test_alpha_renaming _ =
  let loc = Loc.other __LOC__ in

  (* Create two index terms with different variable names but same structure:
     v_int_123 + v_int_456  vs  v_int_789 + v_int_999 *)

  let sym1_a = Sym.fresh "v_int_123" in
  let sym1_b = Sym.fresh "v_int_456" in
  let sym2_a = Sym.fresh "v_int_789" in
  let sym2_b = Sym.fresh "v_int_999" in

  (* Build: sym1_a + sym1_b *)
  let it1 =
    IT.add_
      (IT.sym_ (sym1_a, BT.Integer, loc), IT.sym_ (sym1_b, BT.Integer, loc))
      loc
  in

  (* Build: sym2_a + sym2_b *)
  let it2 =
    IT.add_
      (IT.sym_ (sym2_a, BT.Integer, loc), IT.sym_ (sym2_b, BT.Integer, loc))
      loc
  in

  let hash1 = CH.hash_index_term it1 in
  let hash2 = CH.hash_index_term it2 in

  (* Both should hash to the same value after alpha-renaming *)
  assert_equal ~msg:"Alpha-equivalent terms should hash the same" hash1 hash2

(* Test that different structures hash differently *)
let test_different_structures _ =
  let loc = Loc.other __LOC__ in

  let sym1 = Sym.fresh "v_int_123" in
  let sym2 = Sym.fresh "v_int_456" in

  (* Build: sym1 + sym2 *)
  let it_add =
    IT.add_ (IT.sym_ (sym1, BT.Integer, loc), IT.sym_ (sym2, BT.Integer, loc)) loc
  in

  (* Build: sym1 - sym2 *)
  let it_sub =
    IT.sub_ (IT.sym_ (sym1, BT.Integer, loc), IT.sym_ (sym2, BT.Integer, loc)) loc
  in

  let hash_add = CH.hash_index_term it_add in
  let hash_sub = CH.hash_index_term it_sub in

  (* Different operations should hash differently *)
  assert_bool "Different operations should hash differently"
    (String.compare hash_add hash_sub <> 0)

(* Test that user-written variable names are preserved *)
let test_user_vars_preserved _ =
  let loc = Loc.other __LOC__ in

  (* User variables (no underscore+digits suffix) *)
  let x = Sym.fresh "x" in
  let y = Sym.fresh "y" in
  let a = Sym.fresh "a" in
  let b = Sym.fresh "b" in

  (* Build: x + y *)
  let it1 =
    IT.add_ (IT.sym_ (x, BT.Integer, loc), IT.sym_ (y, BT.Integer, loc)) loc
  in

  (* Build: a + b *)
  let it2 =
    IT.add_ (IT.sym_ (a, BT.Integer, loc), IT.sym_ (b, BT.Integer, loc)) loc
  in

  let hash1 = CH.hash_index_term it1 in
  let hash2 = CH.hash_index_term it2 in

  (* User variables should NOT be renamed, so these should hash differently *)
  assert_bool "User variables should not be renamed" (String.compare hash1 hash2 <> 0)

(* Test that same generated variable names hash the same *)
let test_same_generated_vars _ =
  let loc = Loc.other __LOC__ in

  let sym1 = Sym.fresh "tmp_100" in
  let sym2 = Sym.fresh "tmp_200" in

  (* Build two identical structures with same generated variable naming pattern *)
  let it1 = IT.sym_ (sym1, BT.Integer, loc) in
  let it2 = IT.sym_ (sym2, BT.Integer, loc) in

  let hash1 = CH.hash_index_term it1 in
  let hash2 = CH.hash_index_term it2 in

  (* Same structure with generated vars should hash the same *)
  assert_equal ~msg:"Same structure with generated vars" hash1 hash2

let suite =
  "ContentHash"
  >::: [ "alpha_renaming" >:: test_alpha_renaming;
         "different_structures" >:: test_different_structures;
         "user_vars_preserved" >:: test_user_vars_preserved;
         "same_generated_vars" >:: test_same_generated_vars
       ]


let () = run_test_tt_main suite
