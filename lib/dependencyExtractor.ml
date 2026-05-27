(** Extract all dependencies from CN definitions *)

module IT = IndexTerms
module BT = BaseTypes
module AT = ArgumentTypes
module LAT = LogicalArgumentTypes
module RT = ReturnTypes
module LRT = LogicalReturnTypes
module Req = Request
module Mu = Mucore

(** Extract predicates used in an index term *)
let rec extract_predicates_from_it (it : IT.t) : Sym.t list =
  let (IT (term, _, _)) = it in
  match term with
  | Terms.Apply (name, args) ->
    (* Predicate application *)
    name :: List.concat_map extract_predicates_from_it args
  | Terms.Const _ | Terms.Sym _ -> []
  | Terms.Unop (_, t) -> extract_predicates_from_it t
  | Terms.Binop (_, t1, t2) ->
    extract_predicates_from_it t1 @ extract_predicates_from_it t2
  | Terms.ITE (t1, t2, t3) ->
    extract_predicates_from_it t1
    @ extract_predicates_from_it t2
    @ extract_predicates_from_it t3
  | Terms.EachI (_, t) -> extract_predicates_from_it t
  | Terms.Tuple ts -> List.concat_map extract_predicates_from_it ts
  | Terms.NthTuple (_, t) -> extract_predicates_from_it t
  | Terms.Struct (_, members) | Terms.Record members ->
    List.concat_map (fun (_, t) -> extract_predicates_from_it t) members
  | Terms.StructMember (t, _) | Terms.RecordMember (t, _) -> extract_predicates_from_it t
  | Terms.StructUpdate ((t1, _), t2) | Terms.RecordUpdate ((t1, _), t2) ->
    extract_predicates_from_it t1 @ extract_predicates_from_it t2
  | Terms.Cast (_, t) -> extract_predicates_from_it t
  | Terms.MemberShift (t, _, _) -> extract_predicates_from_it t
  | Terms.ArrayShift { base; index; _ } ->
    extract_predicates_from_it base @ extract_predicates_from_it index
  | Terms.CopyAllocId { addr; loc } ->
    extract_predicates_from_it addr @ extract_predicates_from_it loc
  | Terms.HasAllocId t -> extract_predicates_from_it t
  | Terms.SizeOf _ | Terms.OffsetOf _ | Terms.Nil _ | Terms.CN_None _ -> []
  | Terms.Cons (t1, t2) -> extract_predicates_from_it t1 @ extract_predicates_from_it t2
  | Terms.Head t | Terms.Tail t -> extract_predicates_from_it t
  | Terms.Representable (_, t) | Terms.Good (_, t) | Terms.WrapI (_, t) ->
    extract_predicates_from_it t
  | Terms.Aligned { t; align } ->
    extract_predicates_from_it t @ extract_predicates_from_it align
  | Terms.MapConst (_, t) -> extract_predicates_from_it t
  | Terms.MapSet (t1, t2, t3) ->
    extract_predicates_from_it t1
    @ extract_predicates_from_it t2
    @ extract_predicates_from_it t3
  | Terms.MapGet (t1, t2) -> extract_predicates_from_it t1 @ extract_predicates_from_it t2
  | Terms.MapDef (_, t) -> extract_predicates_from_it t
  | Terms.Let ((_, t1), t2) ->
    extract_predicates_from_it t1 @ extract_predicates_from_it t2
  | Terms.Match (t, cases) ->
    extract_predicates_from_it t
    @ List.concat_map (fun (_, body) -> extract_predicates_from_it body) cases
  | Terms.Constructor (_, members) ->
    List.concat_map (fun (_, t) -> extract_predicates_from_it t) members
  | Terms.CN_Some t | Terms.IsSome t | Terms.GetOpt t -> extract_predicates_from_it t


(** Extract predicates from a logical constraint *)
let extract_predicates_from_lc (lc : LogicalConstraints.t) : Sym.t list =
  match lc with
  | LogicalConstraints.T it -> extract_predicates_from_it it
  | LogicalConstraints.Forall ((_, _), it) -> extract_predicates_from_it it


(** Extract predicates from a logical argument type *)
let rec extract_predicates_from_lat (lat : 'a LAT.t) : Sym.t list =
  match lat with
  | LAT.Define ((_, it), _, lat) ->
    extract_predicates_from_it it @ extract_predicates_from_lat lat
  | LAT.Resource ((_, (req, _)), _, lat) ->
    (match req with
     | Req.P { name; pointer; iargs } ->
       (* Resource predicate usage *)
       let name_sym = match name with Req.PName sym -> [ sym ] | Req.Owned _ -> [] in
       name_sym
       @ extract_predicates_from_it pointer
       @ List.concat_map extract_predicates_from_it iargs
       @ extract_predicates_from_lat lat
     | Req.Q _ -> extract_predicates_from_lat lat)
  | LAT.Constraint (lc, _, lat) ->
    extract_predicates_from_lc lc @ extract_predicates_from_lat lat
  | LAT.I _ -> []


(** Extract predicates from an argument type *)
let rec extract_predicates_from_at (at : 'a AT.t) : Sym.t list =
  match at with
  | AT.Computational ((_, _), _, at) | AT.Ghost ((_, _), _, at) ->
    extract_predicates_from_at at
  | AT.L lat -> extract_predicates_from_lat lat


(** Extract predicates used by a function spec *)
let extract_predicate_uses_from_spec (ft : AT.ft option) : Sym.t list =
  match ft with
  | None -> []
  | Some ft ->
    let preds_from_args = extract_predicates_from_at ft in
    (* Extract from return type: RT.Computational wraps LRT.t *)
    let preds_from_ret =
      match AT.get_return ft with
      | RT.Computational ((_, _bt), _, lrt) ->
        let rec extract_from_lrt (lrt : LRT.t) : Sym.t list =
          match lrt with
          | LRT.Define ((_, it2), _, lrt2) ->
            extract_predicates_from_it it2 @ extract_from_lrt lrt2
          | LRT.Resource ((_, (req, _)), _, lrt2) ->
            (match req with
             | Req.P { name; pointer; iargs } ->
               let name_sym =
                 match name with Req.PName sym -> [ sym ] | Req.Owned _ -> []
               in
               name_sym
               @ extract_predicates_from_it pointer
               @ List.concat_map extract_predicates_from_it iargs
               @ extract_from_lrt lrt2
             | Req.Q _ -> extract_from_lrt lrt2)
          | LRT.Constraint (lc, _, lrt2) ->
            extract_predicates_from_lc lc @ extract_from_lrt lrt2
          | LRT.I -> []
        in
        extract_from_lrt lrt
    in
    List.sort_uniq Sym.compare (preds_from_args @ preds_from_ret)


(** Extract predicates used by a predicate definition *)
let extract_predicate_uses_from_predicate (pred : Definition.Predicate.t) : Sym.t list =
  match pred.clauses with
  | None -> []
  | Some clauses ->
    List.concat_map
      (fun (clause : Definition.Clause.t) ->
         (* Extract from guard *)
         let guard_preds = extract_predicates_from_it clause.guard in
         (* Extract from packing_ft *)
         let packing_preds = extract_predicates_from_lat clause.packing_ft in
         guard_preds @ packing_preds)
      clauses
    |> List.sort_uniq Sym.compare


(** Extract logical functions used in an index term *)
let rec extract_logical_functions_from_it (it : IT.t) : Sym.t list =
  let (IT (term, _, _)) = it in
  match term with
  | Terms.Apply (name, args) ->
    (* Could be either predicate or logical function - we'll distinguish later *)
    name :: List.concat_map extract_logical_functions_from_it args
  | Terms.Const _ | Terms.Sym _ -> []
  | Terms.Unop (_, t) -> extract_logical_functions_from_it t
  | Terms.Binop (_, t1, t2) ->
    extract_logical_functions_from_it t1 @ extract_logical_functions_from_it t2
  | Terms.ITE (t1, t2, t3) ->
    extract_logical_functions_from_it t1
    @ extract_logical_functions_from_it t2
    @ extract_logical_functions_from_it t3
  | Terms.EachI (_, t) -> extract_logical_functions_from_it t
  | Terms.Tuple ts -> List.concat_map extract_logical_functions_from_it ts
  | Terms.NthTuple (_, t) -> extract_logical_functions_from_it t
  | Terms.Struct (_, members) | Terms.Record members ->
    List.concat_map (fun (_, t) -> extract_logical_functions_from_it t) members
  | Terms.StructMember (t, _) | Terms.RecordMember (t, _) ->
    extract_logical_functions_from_it t
  | Terms.StructUpdate ((t1, _), t2) | Terms.RecordUpdate ((t1, _), t2) ->
    extract_logical_functions_from_it t1 @ extract_logical_functions_from_it t2
  | Terms.Cast (_, t) -> extract_logical_functions_from_it t
  | Terms.MemberShift (t, _, _) -> extract_logical_functions_from_it t
  | Terms.ArrayShift { base; index; _ } ->
    extract_logical_functions_from_it base @ extract_logical_functions_from_it index
  | Terms.CopyAllocId { addr; loc } ->
    extract_logical_functions_from_it addr @ extract_logical_functions_from_it loc
  | Terms.HasAllocId t -> extract_logical_functions_from_it t
  | Terms.SizeOf _ | Terms.OffsetOf _ | Terms.Nil _ | Terms.CN_None _ -> []
  | Terms.Cons (t1, t2) ->
    extract_logical_functions_from_it t1 @ extract_logical_functions_from_it t2
  | Terms.Head t | Terms.Tail t -> extract_logical_functions_from_it t
  | Terms.Representable (_, t) | Terms.Good (_, t) | Terms.WrapI (_, t) ->
    extract_logical_functions_from_it t
  | Terms.Aligned { t; align } ->
    extract_logical_functions_from_it t @ extract_logical_functions_from_it align
  | Terms.MapConst (_, t) -> extract_logical_functions_from_it t
  | Terms.MapSet (t1, t2, t3) ->
    extract_logical_functions_from_it t1
    @ extract_logical_functions_from_it t2
    @ extract_logical_functions_from_it t3
  | Terms.MapGet (t1, t2) ->
    extract_logical_functions_from_it t1 @ extract_logical_functions_from_it t2
  | Terms.MapDef (_, t) -> extract_logical_functions_from_it t
  | Terms.Let ((_, t1), t2) ->
    extract_logical_functions_from_it t1 @ extract_logical_functions_from_it t2
  | Terms.Match (t, cases) ->
    extract_logical_functions_from_it t
    @ List.concat_map (fun (_, body) -> extract_logical_functions_from_it body) cases
  | Terms.Constructor (_, members) ->
    List.concat_map (fun (_, t) -> extract_logical_functions_from_it t) members
  | Terms.CN_Some t | Terms.IsSome t | Terms.GetOpt t ->
    extract_logical_functions_from_it t


(** Extract struct tags used in a base type *)
let rec extract_structs_from_bt (bt : BT.t) : Sym.t list =
  match bt with
  | BT.Struct tag -> [ tag ]
  | BT.Tuple bts -> List.concat_map extract_structs_from_bt bts
  | BT.Record members ->
    List.concat_map (fun (_, bt) -> extract_structs_from_bt bt) members
  | BT.Map (bt1, bt2) -> extract_structs_from_bt bt1 @ extract_structs_from_bt bt2
  | BT.List bt | BT.Set bt | BT.Option bt -> extract_structs_from_bt bt
  | _ -> []


(** Extract datatype names used in a base type *)
let rec extract_datatypes_from_bt (bt : BT.t) : Sym.t list =
  match bt with
  | BT.Datatype tag -> [ tag ]
  | BT.Tuple bts -> List.concat_map extract_datatypes_from_bt bts
  | BT.Record members ->
    List.concat_map (fun (_, bt) -> extract_datatypes_from_bt bt) members
  | BT.Map (bt1, bt2) -> extract_datatypes_from_bt bt1 @ extract_datatypes_from_bt bt2
  | BT.List bt | BT.Set bt | BT.Option bt -> extract_datatypes_from_bt bt
  | _ -> []


(** Extract struct/datatype usage from a function spec *)
let extract_struct_datatype_uses_from_spec (ft : AT.ft option) : Sym.t list * Sym.t list =
  match ft with
  | None -> ([], [])
  | Some ft ->
    let rec collect_from_at (at : 'a AT.t) : Sym.t list * Sym.t list =
      match at with
      | AT.Computational ((_, bt), _, at) | AT.Ghost ((_, bt), _, at) ->
        let structs1, datatypes1 = collect_from_at at in
        let structs2 = extract_structs_from_bt bt in
        let datatypes2 = extract_datatypes_from_bt bt in
        (structs1 @ structs2, datatypes1 @ datatypes2)
      | AT.L lat -> collect_from_lat lat
    and collect_from_lat (lat : 'a LAT.t) : Sym.t list * Sym.t list =
      match lat with
      | LAT.Define ((_, _it), _, lat) -> collect_from_lat lat
      | LAT.Resource ((_, (_req, bt)), _, lat) ->
        let structs1, datatypes1 = collect_from_lat lat in
        let structs2 = extract_structs_from_bt bt in
        let datatypes2 = extract_datatypes_from_bt bt in
        (structs1 @ structs2, datatypes1 @ datatypes2)
      | LAT.Constraint (_lc, _, lat) -> collect_from_lat lat
      | LAT.I _ -> ([], [])
    in
    let structs, datatypes = collect_from_at ft in
    (List.sort_uniq Sym.compare structs, List.sort_uniq Sym.compare datatypes)


(** Extract predicate name from a request name *)
let extract_pred_name_from_request_name (name : Req.name) : Sym.t option =
  match name with
  | Req.PName sym -> Some sym
  | Req.Owned _ -> None (* Owned is not a predicate dependency *)


(** Extract all predicate symbols from a request *)
let extract_preds_from_request (req : Req.t) : Sym.t list =
  match req with
  | Req.P pred ->
    (* The predicate being called is the main dependency *)
    let pred_name = extract_pred_name_from_request_name pred.name in
    (* Also extract predicates from arguments *)
    let pred_syms_from_its =
      List.concat_map extract_predicates_from_it (pred.pointer :: pred.iargs)
    in
    (match pred_name with
     | Some sym -> sym :: pred_syms_from_its
     | None -> pred_syms_from_its)
  | Req.Q qpred ->
    (* For Q predicates, also extract the name *)
    let pred_name = extract_pred_name_from_request_name qpred.name in
    (* Also extract predicates from arguments *)
    let pred_syms_from_its =
      List.concat_map extract_predicates_from_it (qpred.pointer :: qpred.iargs)
    in
    (match pred_name with
     | Some sym -> sym :: pred_syms_from_its
     | None -> pred_syms_from_its)


(** Extract all predicate symbols from a LAT recursively *)
let rec extract_preds_from_lat (lat : 'a LAT.t) : Sym.t list =
  match lat with
  | LAT.Define ((_, it), _, next) ->
    extract_predicates_from_it it @ extract_preds_from_lat next
  | LAT.Resource ((_, (req, _bt)), _, next) ->
    extract_preds_from_request req @ extract_preds_from_lat next
  | LAT.Constraint (lc, _, next) ->
    (* Extract predicates from LogicalConstraint *)
    let lc_pred_syms = LogicalConstraints.preds_of lc |> Sym.Set.elements in
    lc_pred_syms @ extract_preds_from_lat next
  | LAT.I _ -> []


(** Extract predicate dependencies from a predicate definition *)
let extract_predicate_dependencies (global : Global.t) (pred_sym : Sym.t) : Sym.t list =
  match Sym.Map.find_opt pred_sym global.resource_predicates with
  | None -> []
  | Some pred_def ->
    (match pred_def.Definition.Predicate.clauses with
     | None -> []
     | Some clauses ->
       List.concat_map
         (fun (clause : Definition.Clause.t) ->
            (* Extract predicates from guard *)
            let guard_preds = extract_predicates_from_it clause.guard in
            (* Extract predicates from packing_ft *)
            let packing_preds = extract_preds_from_lat clause.packing_ft in
            guard_preds @ packing_preds)
         clauses
       |> List.sort_uniq Sym.compare)


(** Extract logical function uses from a predicate definition *)
let extract_logical_function_uses_from_predicate
      (global : Global.t)
      (pred_def : Definition.Predicate.t)
  : Sym.t list
  =
  match pred_def.Definition.Predicate.clauses with
  | None -> []
  | Some clauses ->
    List.concat_map
      (fun (clause : Definition.Clause.t) ->
         (* Extract from guard *)
         let guard_applies = extract_predicates_from_it clause.guard in
         let guard_lfs =
           List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) guard_applies
         in
         (* Extract from packing_ft *)
         let packing_applies = extract_preds_from_lat clause.packing_ft in
         let packing_lfs =
           List.filter
             (fun sym -> Sym.Map.mem sym global.logical_functions)
             packing_applies
         in
         guard_lfs @ packing_lfs)
      clauses
    |> List.sort_uniq Sym.compare


(** Extract struct/datatype uses from a predicate definition *)
let extract_struct_datatype_uses_from_predicate (pred_def : Definition.Predicate.t)
  : Sym.t list * Sym.t list
  =
  (* Extract from predicate return type (oarg) *)
  let _loc, oarg_bt = pred_def.Definition.Predicate.oarg in
  let ret_structs = extract_structs_from_bt oarg_bt in
  let ret_datatypes = extract_datatypes_from_bt oarg_bt in
  (* Extract from predicate argument types (iargs) *)
  let arg_types = List.map snd pred_def.Definition.Predicate.iargs in
  let arg_structs = List.concat_map extract_structs_from_bt arg_types in
  let arg_datatypes = List.concat_map extract_datatypes_from_bt arg_types in
  (* Extract from clause bodies *)
  let clause_structs, clause_datatypes =
    match pred_def.Definition.Predicate.clauses with
    | None -> ([], [])
    | Some clauses ->
      let structs_datatypes =
        List.concat_map
          (fun (clause : Definition.Clause.t) ->
             (* Extract from packing_ft types *)
             let rec collect_from_lat (lat : 'a LAT.t) : Sym.t list * Sym.t list =
               match lat with
               | LAT.Define ((_, _it), _, lat) -> collect_from_lat lat
               | LAT.Resource ((_, (_req, bt)), _, lat) ->
                 let structs1, datatypes1 = collect_from_lat lat in
                 let structs2 = extract_structs_from_bt bt in
                 let datatypes2 = extract_datatypes_from_bt bt in
                 (structs1 @ structs2, datatypes1 @ datatypes2)
               | LAT.Constraint (_lc, _, lat) -> collect_from_lat lat
               | LAT.I _ -> ([], [])
             in
             let s, d = collect_from_lat clause.packing_ft in
             [ (s, d) ])
          clauses
      in
      let structs = List.concat_map fst structs_datatypes in
      let datatypes = List.concat_map snd structs_datatypes in
      (structs, datatypes)
  in
  let all_structs =
    ret_structs @ arg_structs @ clause_structs |> List.sort_uniq Sym.compare
  in
  let all_datatypes =
    ret_datatypes @ arg_datatypes @ clause_datatypes |> List.sort_uniq Sym.compare
  in
  (all_structs, all_datatypes)


(** Extract struct/datatype uses from a logical function definition *)
let extract_struct_datatype_uses_from_logical_function (lf_def : Definition.Function.t)
  : Sym.t list * Sym.t list
  =
  (* Extract from return type and argument types *)
  let arg_types = List.map snd lf_def.Definition.Function.args in
  let ret_type = lf_def.Definition.Function.return_bt in
  let all_types = ret_type :: arg_types in
  let structs =
    List.concat_map extract_structs_from_bt all_types |> List.sort_uniq Sym.compare
  in
  let datatypes =
    List.concat_map extract_datatypes_from_bt all_types |> List.sort_uniq Sym.compare
  in
  (structs, datatypes)


(** Extract logical function dependencies from a logical function definition *)
let extract_logical_function_dependencies (global : Global.t) (lf_sym : Sym.t)
  : Sym.t list
  =
  match Sym.Map.find_opt lf_sym global.logical_functions with
  | None -> []
  | Some lf_def ->
    (match lf_def.Definition.Function.body with
     | Definition.Function.Uninterp -> []
     | Definition.Function.Def it | Definition.Function.Rec_Def it ->
       (* Extract all Apply nodes *)
       let all_applies = extract_predicates_from_it it in
       (* Filter to only logical functions (not predicates) *)
       List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) all_applies
       |> List.sort_uniq Sym.compare)


(** Extract logical functions from CN statements (assertions, split_case, etc.) *)
let rec extract_logical_functions_from_cn_statements
          (_global : Global.t)
          (_stmts : 'a list) (* Cnstatement.statement Cnprog.t list or similar *)
  : Sym.t list
  =
  (* CN statements contain logical constraints with IT expressions *)
  (* We'll extract from LogicalConstraints which contain IT expressions *)
  (* This is a simplified extraction - the actual CN statement structure may vary *)
  []


(* Placeholder for now - need to understand Cnstatement structure *)

(** Extract logical functions from loop invariants in arguments_l *)
let rec extract_logical_functions_from_arguments_l
          (global : Global.t)
          (args_l : 'i Mu.arguments_l)
  : Sym.t list
  =
  match args_l with
  | Mu.Define ((_, it), _, rest) ->
    let all_applies = extract_predicates_from_it it in
    let it_lfs =
      List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) all_applies
    in
    it_lfs @ extract_logical_functions_from_arguments_l global rest
  | Mu.Resource (_, _, rest) -> extract_logical_functions_from_arguments_l global rest
  | Mu.Constraint (lc, _, rest) ->
    let lc_syms = LogicalConstraints.preds_of lc |> Sym.Set.elements in
    let lc_lfs =
      List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) lc_syms
    in
    lc_lfs @ extract_logical_functions_from_arguments_l global rest
  | Mu.I _ -> []


(** Extract logical functions from loop invariants *)
let extract_logical_functions_from_loop_invariants
      (global : Global.t)
      (labels : ('a, 'b Mu.label_def) Pmap.map)
  : Sym.t list
  =
  Pmap.fold
    (fun _label label_def acc ->
       match label_def with
       | Mu.Loop (_, loop_args, _, _, _) ->
         (* Loop arguments contain the invariants *)
         let rec extract_from_args (args : 'i Mu.arguments) : Sym.t list =
           match args with
           | Mu.Computational (_, _, rest) | Mu.Ghost (_, _, rest) ->
             extract_from_args rest
           | Mu.L args_l -> extract_logical_functions_from_arguments_l global args_l
         in
         extract_from_args loop_args @ acc
       | _ -> acc)
    labels
    []


(** Extract logical functions from Mucore expression (including CN annotations) *)
let rec extract_logical_functions_from_expr (global : Global.t) (expr : 'a Mu.expr)
  : Sym.t list
  =
  let (Mu.Expr (_loc, _annots, _bt, expr_)) = expr in
  match expr_ with
  | Mu.Epure _ | Mu.Ememop _ | Mu.Eaction _ | Mu.Eskip -> []
  | Mu.Eccall (_act, _fexpr, _args, cn_progs_opt) ->
    (* CN programs attached to function calls (like assertions) *)
    (match cn_progs_opt with
     | None -> []
     | Some (_loc, _cn_progs) ->
       (* TODO: extract from cn_progs - need to understand Cnprog structure *)
       [])
  | Mu.Eproc _ | Mu.Erun _ -> []
  | Mu.Elet (_pat, _pexpr, body) -> extract_logical_functions_from_expr global body
  | Mu.Eunseq exprs | Mu.End exprs ->
    List.concat_map (extract_logical_functions_from_expr global) exprs
  | Mu.Ewseq (_pat, e1, e2) | Mu.Esseq (_pat, e1, e2) ->
    extract_logical_functions_from_expr global e1
    @ extract_logical_functions_from_expr global e2
  | Mu.Eif (_cond, e1, e2) ->
    extract_logical_functions_from_expr global e1
    @ extract_logical_functions_from_expr global e2
  | Mu.Ebound body -> extract_logical_functions_from_expr global body
  | Mu.CN_progs (_cn_stmts, _cn_progs) ->
    (* CN statements like assert, split_case, etc. *)
    (* TODO: extract from cn_stmts and cn_progs *)
    []


(** Extract logical functions from function body (args_and_body) *)
let extract_logical_functions_from_body
      (global : Global.t)
      (args_and_body : 'a Mu.args_and_body)
  : Sym.t list
  =
  let rec extract_from_args (args : 'i Mu.arguments) : Sym.t list =
    match args with
    | Mu.Computational (_, _, rest) | Mu.Ghost (_, _, rest) -> extract_from_args rest
    | Mu.L args_l ->
      (match args_l with
       | Mu.I (body_expr, labels, _ret_type) ->
         (* Extract from loop invariants *)
         let loop_lfs = extract_logical_functions_from_loop_invariants global labels in
         (* Extract from function body expressions *)
         let body_lfs = extract_logical_functions_from_expr global body_expr in
         loop_lfs @ body_lfs
       | _ ->
         (* Should not reach here for properly formed args_and_body *)
         [])
  in
  extract_from_args args_and_body |> List.sort_uniq Sym.compare


(** Extract logical functions used in a function spec *)
let extract_logical_function_uses_from_spec (global : Global.t) (ft : AT.ft option)
  : Sym.t list
  =
  match ft with
  | None -> []
  | Some ft ->
    (* Extract from arguments (via LAT layer) *)
    let lfs_from_args =
      let rec extract_from_at (at : 'a AT.t) : Sym.t list =
        match at with
        | AT.Computational (_, _, at) | AT.Ghost (_, _, at) -> extract_from_at at
        | AT.L lat -> extract_from_lat lat
      and extract_from_lat (lat : 'a LAT.t) : Sym.t list =
        match lat with
        | LAT.Define ((_, it), _, lat) ->
          let all_applies = extract_predicates_from_it it in
          let it_lfs =
            List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) all_applies
          in
          it_lfs @ extract_from_lat lat
        | LAT.Resource ((_, (_req, _bt)), _, lat) ->
          (* Resources don't contain logical function calls directly, just predicates *)
          extract_from_lat lat
        | LAT.Constraint (lc, _, lat) ->
          (* Extract logical functions from constraints *)
          let lc_syms = LogicalConstraints.preds_of lc |> Sym.Set.elements in
          let lc_lfs =
            List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) lc_syms
          in
          lc_lfs @ extract_from_lat lat
        | LAT.I _ -> []
      in
      extract_from_at ft
    in
    (* Extract from return type *)
    let lfs_from_ret =
      match AT.get_return ft with
      | RT.Computational ((_, _bt), _, lrt) ->
        let rec extract_from_lrt (lrt : LRT.t) : Sym.t list =
          match lrt with
          | LRT.Define ((_, it), _, lrt2) ->
            let all_applies = extract_predicates_from_it it in
            let it_lfs =
              List.filter
                (fun sym -> Sym.Map.mem sym global.logical_functions)
                all_applies
            in
            it_lfs @ extract_from_lrt lrt2
          | LRT.Resource ((_, (_req, _)), _, lrt2) ->
            (* Resources don't contain logical function calls directly *)
            extract_from_lrt lrt2
          | LRT.Constraint (lc, _, lrt2) ->
            let lc_syms = LogicalConstraints.preds_of lc |> Sym.Set.elements in
            let lc_lfs =
              List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) lc_syms
            in
            lc_lfs @ extract_from_lrt lrt2
          | LRT.I -> []
        in
        extract_from_lrt lrt
    in
    List.sort_uniq Sym.compare (lfs_from_args @ lfs_from_ret)


(** Extract function symbol from generic_name *)
let extract_sym_from_generic_name (name : Sym.t Cerb_frontend.Core.generic_name)
  : Sym.t option
  =
  match name with Cerb_frontend.Core.Sym sym -> Some sym | _ -> None


(** Extract function calls from a Mucore expr *)
let rec extract_function_calls_from_expr (expr : 'a Mu.expr) : Sym.t list =
  (* Simplified: just extract from PEcall in pexprs *)
  (* Full traversal would be complex, so we'll do a simpler recursive search *)
  let rec from_pexpr (pexpr : 'a Mu.pexpr) : Sym.t list =
    let (Mu.Pexpr (_, _, _, pexpr_)) = pexpr in
    match pexpr_ with
    | Mu.PEcall (fname, args) ->
      let fsym_opt = extract_sym_from_generic_name fname in
      let arg_calls = List.concat_map from_pexpr args in
      (match fsym_opt with Some fsym -> fsym :: arg_calls | None -> arg_calls)
    | Mu.PEsym _ | Mu.PEval _ | Mu.PEundef _ -> []
    | Mu.PEconstrained constrs -> List.concat_map (fun (_, pe) -> from_pexpr pe) constrs
    | Mu.PEerror (_, pe)
    | Mu.PEmember_shift (pe, _, _)
    | Mu.PEmemop (_, pe)
    | Mu.PEnot pe
    | Mu.PEcfunction pe
    | Mu.PEmemberof (_, _, pe)
    | Mu.PEunion (_, _, pe) ->
      from_pexpr pe
    | Mu.PEctor (_, pes) -> List.concat_map from_pexpr pes
    | Mu.PEarray_shift (pe1, _, pe2)
    | Mu.PEcatch_exceptional_condition (_, _, pe1, pe2)
    | Mu.PEwrapI (_, _, pe1, pe2)
    | Mu.PEop (_, pe1, pe2)
    | Mu.PEconv_int (pe1, pe2)
    | Mu.PEare_compatible (pe1, pe2) ->
      from_pexpr pe1 @ from_pexpr pe2
    | Mu.PEstruct (_, fields) -> List.concat_map (fun (_, pe) -> from_pexpr pe) fields
    | Mu.PElet (_, pe1, pe2) -> from_pexpr pe1 @ from_pexpr pe2
    | Mu.PEif (pe1, pe2, pe3) -> from_pexpr pe1 @ from_pexpr pe2 @ from_pexpr pe3
  in
  let (Mu.Expr (_, _, _, expr_)) = expr in
  match expr_ with
  | Mu.Epure pe -> from_pexpr pe
  | Mu.Ememop (_, pes) -> List.concat_map from_pexpr pes
  | Mu.Eaction _ -> [] (* Simplified - actions don't call functions typically *)
  | Mu.Eskip -> []
  | Mu.Eccall (_, f_pe, pes, _) ->
    (* C function call - the function pointer expression might contain the function symbol *)
    (* In practice, f_pe is often PEsym containing the function symbol *)
    let f_calls =
      match f_pe with
      | Mu.Pexpr (_, _, _, Mu.PEsym fsym) -> [ fsym ]
      | _ -> from_pexpr f_pe
    in
    f_calls @ List.concat_map from_pexpr pes
  | Mu.Eproc (fname, pes) ->
    (* Procedure call *)
    let fsym_opt = extract_sym_from_generic_name fname in
    let arg_calls = List.concat_map from_pexpr pes in
    (match fsym_opt with Some fsym -> fsym :: arg_calls | None -> arg_calls)
  | Mu.Elet (_, pe, e) ->
    (* Let binding - recurse into both the bound expression and the body *)
    from_pexpr pe @ extract_function_calls_from_expr e
  | Mu.Eunseq exprs | Mu.End exprs ->
    (* Multiple expressions - recurse into all *)
    List.concat_map extract_function_calls_from_expr exprs
  | Mu.Esseq (_, e1, e2) | Mu.Ewseq (_, e1, e2) ->
    (* Sequential - recurse into both *)
    extract_function_calls_from_expr e1 @ extract_function_calls_from_expr e2
  | Mu.Eif (pe, e1, e2) ->
    (* Conditional - check condition and both branches *)
    from_pexpr pe
    @ extract_function_calls_from_expr e1
    @ extract_function_calls_from_expr e2
  | Mu.Ebound e ->
    (* Bound expression - recurse *)
    extract_function_calls_from_expr e
  | Mu.Erun (fsym, pes) ->
    (* Run statement (similar to procedure call) *)
    let arg_calls = List.concat_map from_pexpr pes in
    fsym :: arg_calls
  | Mu.CN_progs _ -> []


(** Extract all function calls from a function body (args_and_body) *)
let extract_function_calls_from_body (args_and_body : 'a Mu.args_and_body) : Sym.t list =
  (* args_and_body is (expr * label_map * return_type) arguments *)
  (* We need to extract the expr from the arguments structure *)
  let rec get_body_from_arguments (args : 'i Mu.arguments) : 'i option =
    match args with
    | Mu.Computational (_, _, rest) | Mu.Ghost (_, _, rest) ->
      get_body_from_arguments rest
    | Mu.L args_l -> get_body_from_arguments_l args_l
  and get_body_from_arguments_l (args_l : 'i Mu.arguments_l) : 'i option =
    match args_l with
    | Mu.Define (_, _, rest) | Mu.Resource (_, _, rest) | Mu.Constraint (_, _, rest) ->
      get_body_from_arguments_l rest
    | Mu.I body -> Some body
  in
  match get_body_from_arguments args_and_body with
  | Some (expr, _, _) ->
    (* body is a tuple (expr, label_map, return_type) *)
    extract_function_calls_from_expr expr |> List.sort_uniq Sym.compare
  | None -> []


(** Extract predicate dependencies from a lemma type *)
let extract_predicate_uses_from_lemma (lemma_typ : AT.lemmat) : Sym.t list =
  (* lemma_typ is AT.t with LRT.t *)
  let preds_from_args = extract_predicates_from_at lemma_typ in
  (* LRT.t is the return type for lemmata, already have it from the AT.t structure *)
  (* Just use the args extraction, lemmata don't have return values in the same way *)
  preds_from_args


(** Extract logical function dependencies from a lemma type *)
let extract_logical_function_uses_from_lemma (global : Global.t) (lemma_typ : AT.lemmat)
  : Sym.t list
  =
  (* Extract from the AT.t structure *)
  let rec extract_from_at (at : 'a AT.t) : Sym.t list =
    match at with
    | AT.Computational (_, _, at) | AT.Ghost (_, _, at) -> extract_from_at at
    | AT.L lat -> extract_from_lat lat
  and extract_from_lat (lat : 'a LAT.t) : Sym.t list =
    match lat with
    | LAT.Define ((_, it), _, lat) ->
      let all_applies = extract_predicates_from_it it in
      let it_lfs =
        List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) all_applies
      in
      it_lfs @ extract_from_lat lat
    | LAT.Resource ((_, (_req, _bt)), _, lat) -> extract_from_lat lat
    | LAT.Constraint (lc, _, lat) ->
      let lc_syms = LogicalConstraints.preds_of lc |> Sym.Set.elements in
      let lc_lfs =
        List.filter (fun sym -> Sym.Map.mem sym global.logical_functions) lc_syms
      in
      lc_lfs @ extract_from_lat lat
    | LAT.I _ -> []
  in
  extract_from_at lemma_typ |> List.sort_uniq Sym.compare


(** Extract struct/datatype dependencies from a lemma type *)
let extract_struct_datatype_uses_from_lemma (lemma_typ : AT.lemmat)
  : Sym.t list * Sym.t list
  =
  let rec collect_from_at (at : 'a AT.t) : Sym.t list * Sym.t list =
    match at with
    | AT.Computational ((_, bt), _, at) | AT.Ghost ((_, bt), _, at) ->
      let structs1, datatypes1 = collect_from_at at in
      let structs2 = extract_structs_from_bt bt in
      let datatypes2 = extract_datatypes_from_bt bt in
      (structs1 @ structs2, datatypes1 @ datatypes2)
    | AT.L lat -> collect_from_lat lat
  and collect_from_lat (lat : 'a LAT.t) : Sym.t list * Sym.t list =
    match lat with
    | LAT.Define ((_, _it), _, lat) -> collect_from_lat lat
    | LAT.Resource ((_, (_req, bt)), _, lat) ->
      let structs1, datatypes1 = collect_from_lat lat in
      let structs2 = extract_structs_from_bt bt in
      let datatypes2 = extract_datatypes_from_bt bt in
      (structs1 @ structs2, datatypes1 @ datatypes2)
    | LAT.Constraint (_lc, _, lat) -> collect_from_lat lat
    | LAT.I _ -> ([], [])
  in
  let structs, datatypes = collect_from_at lemma_typ in
  (List.sort_uniq Sym.compare structs, List.sort_uniq Sym.compare datatypes)
