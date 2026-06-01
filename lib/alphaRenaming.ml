(** Canonical alpha-renaming for deterministic hashing

    This module provides alpha-renaming that produces canonical, deterministic
    names for bound variables. Unlike the existing alpha_rename functions that
    use fresh_same to generate unique symbols, these functions produce the same
    canonical names each time for semantically equivalent terms.

    This is essential for content-based hashing where semantically equivalent
    definitions must hash to the same value.
*)

module IT = IndexTerms
module LAT = LogicalArgumentTypes
module AT = ArgumentTypes
module RT = ReturnTypes
module LRT = LogicalReturnTypes
module LC = LogicalConstraints
module Req = Request
module BT = BaseTypes
module Mucore = Mucore
module Sym_map = Map.Make (Sym)

(** Renaming context tracks variable renamings during traversal *)
type ctx =
  { bindings : Sym.t Sym_map.t;
    (* Map from original to canonical *)
    counter : int (* Counter for generating canonical names *)
  }

let empty_ctx = { bindings = Sym_map.empty; counter = 0 }

(** Check if a symbol name looks CN-generated (contains underscore followed by digits) *)
let is_generated_sym (sym : Sym.t) : bool =
  let name = Sym.pp_string sym in
  (* Matches patterns like: i_1234, tmp_5678, v_9012, etc. *)
  Str.string_match (Str.regexp "^[a-zA-Z_][a-zA-Z0-9_]*_[0-9]+$") name 0


(** Generate canonical name for a variable based on order.
    Uses a fixed prefix 'v' to ensure complete normalization regardless of original name. *)
let canonical_name (order : int) (_original : Sym.t) : Sym.t =
  Sym.fresh (Printf.sprintf "v_%d" order)


(** Get or create canonical name for a symbol in the current context.
    For deterministic hashing of function specs, we always generate canonical
    names, even for user-written variables. *)
let bind_canonical (ctx : ctx) (sym : Sym.t) : Sym.t * ctx =
  match Sym_map.find_opt sym ctx.bindings with
  | Some canonical -> (canonical, ctx)
  | None ->
    (* Generate new canonical name based on position *)
    let canonical = canonical_name ctx.counter sym in
    let new_ctx =
      { bindings = Sym_map.add sym canonical ctx.bindings; counter = ctx.counter + 1 }
    in
    (canonical, new_ctx)


(** Lookup a symbol in the renaming context.
    If not found, return the original symbol (it might be a global or builtin) *)
let lookup (ctx : ctx) (sym : Sym.t) : Sym.t =
  match Sym_map.find_opt sym ctx.bindings with Some s -> s | None -> sym


(** Alpha-rename an index term *)
let rec rename_it (ctx : ctx) (it : IT.t) : IT.t * ctx =
  let (IT (term, bt, loc)) = it in
  let term', ctx' =
    match term with
    | Terms.Const _ -> (term, ctx)
    | Terms.Sym s ->
      let s' = lookup ctx s in
      (Terms.Sym s', ctx)
    | Terms.Unop (op, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.Unop (op, t'), ctx')
    | Terms.Binop (op, t1, t2) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      (Terms.Binop (op, t1', t2'), ctx2)
    | Terms.ITE (t1, t2, t3) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      let t3', ctx3 = rename_it ctx2 t3 in
      (Terms.ITE (t1', t2', t3'), ctx3)
    | Terms.EachI ((i_sym, (s, bt_s), info), t) ->
      (* Bind the quantified variable *)
      let s', ctx1 = bind_canonical ctx s in
      let t', ctx2 = rename_it ctx1 t in
      (Terms.EachI ((i_sym, (s', bt_s), info), t'), ctx2)
    | Terms.Tuple ts ->
      let ts', ctx' = rename_list ctx ts in
      (Terms.Tuple ts', ctx')
    | Terms.NthTuple (n, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.NthTuple (n, t'), ctx')
    | Terms.Struct (tag, members) ->
      let members', ctx' = rename_members ctx members in
      (Terms.Struct (tag, members'), ctx')
    | Terms.StructMember (t, member) ->
      let t', ctx' = rename_it ctx t in
      (Terms.StructMember (t', member), ctx')
    | Terms.StructUpdate ((t1, member), t2) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      (Terms.StructUpdate ((t1', member), t2'), ctx2)
    | Terms.Record members ->
      let members', ctx' = rename_members ctx members in
      (Terms.Record members', ctx')
    | Terms.RecordMember (t, member) ->
      let t', ctx' = rename_it ctx t in
      (Terms.RecordMember (t', member), ctx')
    | Terms.RecordUpdate ((t1, member), t2) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      (Terms.RecordUpdate ((t1', member), t2'), ctx2)
    | Terms.Cast (cbt, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.Cast (cbt, t'), ctx')
    | Terms.MemberShift (t, tag, id) ->
      let t', ctx' = rename_it ctx t in
      (Terms.MemberShift (t', tag, id), ctx')
    | Terms.ArrayShift { base; ct; index } ->
      let base', ctx1 = rename_it ctx base in
      let index', ctx2 = rename_it ctx1 index in
      (Terms.ArrayShift { base = base'; ct; index = index' }, ctx2)
    | Terms.CopyAllocId { addr; loc = loc_t } ->
      let addr', ctx1 = rename_it ctx addr in
      let loc', ctx2 = rename_it ctx1 loc_t in
      (Terms.CopyAllocId { addr = addr'; loc = loc' }, ctx2)
    | Terms.HasAllocId loc_t ->
      let loc', ctx' = rename_it ctx loc_t in
      (Terms.HasAllocId loc', ctx')
    | Terms.SizeOf _ | Terms.OffsetOf _ | Terms.Nil _ -> (term, ctx)
    | Terms.Cons (t1, t2) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      (Terms.Cons (t1', t2'), ctx2)
    | Terms.Head t ->
      let t', ctx' = rename_it ctx t in
      (Terms.Head t', ctx')
    | Terms.Tail t ->
      let t', ctx' = rename_it ctx t in
      (Terms.Tail t', ctx')
    | Terms.Representable (sct, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.Representable (sct, t'), ctx')
    | Terms.Good (sct, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.Good (sct, t'), ctx')
    | Terms.WrapI (ity, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.WrapI (ity, t'), ctx')
    | Terms.Aligned { t; align } ->
      let t', ctx1 = rename_it ctx t in
      let align', ctx2 = rename_it ctx1 align in
      (Terms.Aligned { t = t'; align = align' }, ctx2)
    | Terms.MapConst (bt_m, t) ->
      let t', ctx' = rename_it ctx t in
      (Terms.MapConst (bt_m, t'), ctx')
    | Terms.MapSet (t1, t2, t3) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      let t3', ctx3 = rename_it ctx2 t3 in
      (Terms.MapSet (t1', t2', t3'), ctx3)
    | Terms.MapGet (t1, t2) ->
      let t1', ctx1 = rename_it ctx t1 in
      let t2', ctx2 = rename_it ctx1 t2 in
      (Terms.MapGet (t1', t2'), ctx2)
    | Terms.MapDef ((s, bt_s), t) ->
      (* Bind the lambda variable *)
      let s', ctx1 = bind_canonical ctx s in
      let t', ctx2 = rename_it ctx1 t in
      (Terms.MapDef ((s', bt_s), t'), ctx2)
    | Terms.Apply (pred, ts) ->
      let ts', ctx' = rename_list ctx ts in
      (Terms.Apply (pred, ts'), ctx')
    | Terms.Let ((nm, t1), t2) ->
      let t1', ctx1 = rename_it ctx t1 in
      (* Bind the let-bound variable *)
      let nm', ctx2 = bind_canonical ctx1 nm in
      let t2', ctx3 = rename_it ctx2 t2 in
      (Terms.Let ((nm', t1'), t2'), ctx3)
    | Terms.Match (t, cases) ->
      let t', ctx1 = rename_it ctx t in
      let cases', ctx2 = rename_cases ctx1 cases in
      (Terms.Match (t', cases'), ctx2)
    | Terms.Constructor (ctor, args) ->
      let args', ctx' = rename_members ctx args in
      (Terms.Constructor (ctor, args'), ctx')
    | Terms.CN_None _ -> (term, ctx)
    | Terms.CN_Some t ->
      let t', ctx' = rename_it ctx t in
      (Terms.CN_Some t', ctx')
    | Terms.IsSome t ->
      let t', ctx' = rename_it ctx t in
      (Terms.IsSome t', ctx')
    | Terms.GetOpt t ->
      let t', ctx' = rename_it ctx t in
      (Terms.GetOpt t', ctx')
  in
  (IT (term', bt, loc), ctx')


and rename_list ctx ts =
  List.fold_left
    (fun (acc, ctx) t ->
       let t', ctx' = rename_it ctx t in
       (t' :: acc, ctx'))
    ([], ctx)
    ts
  |> fun (ts, ctx) -> (List.rev ts, ctx)


and rename_members ctx members =
  List.fold_left
    (fun (acc, ctx) (id, t) ->
       let t', ctx' = rename_it ctx t in
       ((id, t') :: acc, ctx'))
    ([], ctx)
    members
  |> fun (ms, ctx) -> (List.rev ms, ctx)


and rename_cases ctx cases =
  List.fold_left
    (fun (acc, ctx_outer) (pat, t) ->
       (* Each case has its own binding scope, so we need to track bindings
         but then restore the outer context after processing the case *)
       let pat', ctx_with_pat_bindings = rename_pattern ctx_outer pat in
       let t', _ = rename_it ctx_with_pat_bindings t in
       (* Use original outer context for next case, not the one with pattern bindings *)
       ((pat', t') :: acc, ctx_outer))
    ([], ctx)
    cases
  |> fun (cs, ctx) -> (List.rev cs, ctx)


and rename_pattern ctx (Terms.Pat (pat_, bt, loc)) =
  let pat'', ctx' =
    match pat_ with
    | Terms.PSym s ->
      let s', ctx' = bind_canonical ctx s in
      (Terms.PSym s', ctx')
    | Terms.PWild -> (Terms.PWild, ctx)
    | Terms.PConstructor (ctor, args) ->
      let args', ctx' =
        List.fold_left
          (fun (acc, ctx) (id, pat) ->
             let pat', ctx' = rename_pattern ctx pat in
             ((id, pat') :: acc, ctx'))
          ([], ctx)
          args
      in
      (Terms.PConstructor (ctor, List.rev args'), ctx')
  in
  (Terms.Pat (pat'', bt, loc), ctx')


(** Alpha-rename logical constraints *)
let rename_lc (ctx : ctx) (lc : LC.t) : LC.t * ctx =
  match lc with
  | LC.T lc_it ->
    let lc_it', ctx' = rename_it ctx lc_it in
    (LC.T lc_it', ctx')
  | LC.Forall ((sym, bt), it) ->
    let sym', ctx1 = bind_canonical ctx sym in
    let it', ctx2 = rename_it ctx1 it in
    (LC.Forall ((sym', bt), it'), ctx2)


(** Alpha-rename requests *)
let rename_request (ctx : ctx) (req : Req.t) : Req.t * ctx =
  match req with
  | Req.P p ->
    let pointer', ctx1 = rename_it ctx p.pointer in
    let iargs', ctx2 = rename_list ctx1 p.iargs in
    (Req.P { p with pointer = pointer'; iargs = iargs' }, ctx2)
  | Req.Q qp ->
    (* The quantified variable q needs to be bound *)
    let pointer', ctx1 = rename_it ctx qp.pointer in
    let q_sym, q_bt = qp.q in
    let q_sym', ctx2 = bind_canonical ctx1 q_sym in
    let permission', ctx3 = rename_it ctx2 qp.permission in
    let iargs', ctx4 = rename_list ctx3 qp.iargs in
    ( Req.Q
        { qp with
          pointer = pointer';
          q = (q_sym', q_bt);
          permission = permission';
          iargs = iargs'
        },
      ctx4 )


(** Alpha-rename logical argument types *)
let rec rename_lat (ctx : ctx) (lat : 'i LAT.t) : 'i LAT.t * ctx =
  match lat with
  | LAT.Define ((name, it), info, t) ->
    let it', ctx1 = rename_it ctx it in
    let name', ctx2 = bind_canonical ctx1 name in
    let t', ctx3 = rename_lat ctx2 t in
    (LAT.Define ((name', it'), info, t'), ctx3)
  | LAT.Resource ((name, (re, bt)), info, t) ->
    let re', ctx1 = rename_request ctx re in
    let name', ctx2 = bind_canonical ctx1 name in
    let t', ctx3 = rename_lat ctx2 t in
    (LAT.Resource ((name', (re', bt)), info, t'), ctx3)
  | LAT.Constraint (lc, info, t) ->
    let lc', ctx1 = rename_lc ctx lc in
    let t', ctx2 = rename_lat ctx1 t in
    (LAT.Constraint (lc', info, t'), ctx2)
  | LAT.I i -> (LAT.I i, ctx)


(** Alpha-rename argument types (function specifications) *)
let rec rename_at (ctx : ctx) (at : 'i AT.t) : 'i AT.t * ctx =
  match at with
  | AT.Computational ((name, bt), info, t) ->
    (* Always bind computational arguments for deterministic hashing
       even if they're user-written, since we want semantically equivalent
       specs with different argument names to hash the same *)
    let name', ctx1 = bind_canonical ctx name in
    let t', ctx2 = rename_at ctx1 t in
    (AT.Computational ((name', bt), info, t'), ctx2)
  | AT.Ghost ((name, bt), info, t) ->
    (* Same for ghost arguments *)
    let name', ctx1 = bind_canonical ctx name in
    let t', ctx2 = rename_at ctx1 t in
    (AT.Ghost ((name', bt), info, t'), ctx2)
  | AT.L lat ->
    let lat', ctx' = rename_lat ctx lat in
    (AT.L lat', ctx')


(** Deterministic alpha-rename for ArgumentTypes using substitution.
    Unlike alpha_unique which uses fresh_same (non-deterministic), this uses
    canonical names based on binding position. *)
let rec rename_ft_deterministic (ft : AT.ft) : AT.ft =
  let counter = ref 0 in
  let rec aux (at : RT.t AT.t) : RT.t AT.t =
    match at with
    | AT.Computational ((name, bt), info, t) ->
      let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
      counter := !counter + 1;
      let subst = IT.make_rename ~from:name ~to_:new_name in
      let t' = AT.subst RT.subst subst t in
      let t'' = aux t' in
      AT.Computational ((new_name, bt), info, t'')
    | AT.Ghost ((name, bt), info, t) ->
      let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
      counter := !counter + 1;
      let subst = IT.make_rename ~from:name ~to_:new_name in
      let t' = AT.subst RT.subst subst t in
      let t'' = aux t' in
      AT.Ghost ((new_name, bt), info, t'')
    | AT.L lat -> AT.L (rename_lat_deterministic counter lat)
  in
  aux ft


and rename_lat_deterministic counter (lat : RT.t LAT.t) : RT.t LAT.t =
  match lat with
  | LAT.Define ((name, it), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    let subst = IT.make_rename ~from:name ~to_:new_name in
    let it' = IT.subst subst it in
    let t' = LAT.subst RT.subst subst t in
    let t'' = rename_lat_deterministic counter t' in
    LAT.Define ((new_name, it'), info, t'')
  | LAT.Resource ((name, (re, bt)), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    let subst = IT.make_rename ~from:name ~to_:new_name in
    let re' = Req.subst subst re in
    let t' = LAT.subst RT.subst subst t in
    let t'' = rename_lat_deterministic counter t' in
    LAT.Resource ((new_name, (re', bt)), info, t'')
  | LAT.Constraint (lc, info, t) ->
    let t' = rename_lat_deterministic counter t in
    LAT.Constraint (lc, info, t')
  | LAT.I i -> LAT.I i


(** Alpha-rename a function type (specification) to canonical form *)
let rename_ft (ft : AT.ft) : AT.ft = rename_ft_deterministic ft

(** Alpha-rename a lemma type with fresh context *)
let rec rename_lemmat (lemmat : AT.lemmat) : AT.lemmat =
  let counter = ref 0 in
  let rec aux (at : LRT.t AT.t) : LRT.t AT.t =
    match at with
    | AT.Computational ((name, bt), info, t) ->
      let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
      counter := !counter + 1;
      let subst = IT.make_rename ~from:name ~to_:new_name in
      let t' = AT.subst LRT.subst subst t in
      let t'' = aux t' in
      AT.Computational ((new_name, bt), info, t'')
    | AT.Ghost ((name, bt), info, t) ->
      let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
      counter := !counter + 1;
      let subst = IT.make_rename ~from:name ~to_:new_name in
      let t' = AT.subst LRT.subst subst t in
      let t'' = aux t' in
      AT.Ghost ((new_name, bt), info, t'')
    | AT.L lat -> AT.L (rename_lat_lemma_deterministic counter lat)
  in
  aux lemmat


and rename_lat_lemma_deterministic counter (lat : LRT.t LAT.t) : LRT.t LAT.t =
  match lat with
  | LAT.Define ((name, it), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    let subst = IT.make_rename ~from:name ~to_:new_name in
    let it' = IT.subst subst it in
    let t' = LAT.subst LRT.subst subst t in
    let t'' = rename_lat_lemma_deterministic counter t' in
    LAT.Define ((new_name, it'), info, t'')
  | LAT.Resource ((name, (re, bt)), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    let subst = IT.make_rename ~from:name ~to_:new_name in
    let re' = Req.subst subst re in
    let t' = LAT.subst LRT.subst subst t in
    let t'' = rename_lat_lemma_deterministic counter t' in
    LAT.Resource ((new_name, (re', bt)), info, t'')
  | LAT.Constraint (lc, info, t) ->
    let t' = rename_lat_lemma_deterministic counter t in
    LAT.Constraint (lc, info, t')
  | LAT.I i -> LAT.I i


(** Substitution for Mucore expressions and related structures.
    This implements proper variable substitution throughout the Mucore AST. *)
module MucoreSubst = struct
  (* For rename-only substitutions *)
  type rename_subst = (Sym.t * Sym.t) list

  let make_rename ~from ~to_ : rename_subst = [ (from, to_) ]

  (* Apply rename substitution to a symbol *)
  let subst_sym (s : rename_subst) (sym : Sym.t) : Sym.t =
    (match Sys.getenv_opt "CN_DEBUG_HASH" with
     | Some "1" ->
       Printf.eprintf
         "Looking up symbol %s (id %d) in subst\n%!"
         (Sym.pp_string sym)
         (Sym.num sym)
     | _ -> ());
    match List.find_opt (fun (from, _) -> Sym.equal from sym) s with
    | Some (_, to_) ->
      (match Sys.getenv_opt "CN_DEBUG_HASH" with
       | Some "1" ->
         Printf.eprintf
           "  -> Found! Renaming to %s (id %d)\n%!"
           (Sym.pp_string to_)
           (Sym.num to_)
       | _ -> ());
      to_
    | None ->
      (match Sys.getenv_opt "CN_DEBUG_HASH" with
       | Some "1" -> Printf.eprintf "  -> Not found, keeping %s\n%!" (Sym.pp_string sym)
       | _ -> ());
      sym


  (* Substitute in pexpr *)
  let rec subst_pexpr (s : rename_subst) (Mucore.Pexpr (loc, annots, ty, pe))
    : 'ty Mucore.pexpr
    =
    (match Sys.getenv_opt "CN_DEBUG_HASH" with
     | Some "1" ->
       let pe_name =
         match pe with
         | Mucore.PEsym sym ->
           Printf.sprintf "PEsym %s (id %d)" (Sym.pp_string sym) (Sym.num sym)
         | Mucore.PEval _ -> "PEval"
         | Mucore.PEconstrained _ -> "PEconstrained"
         | Mucore.PEundef _ -> "PEundef"
         | Mucore.PEerror _ -> "PEerror"
         | Mucore.PEctor _ -> "PEctor"
         | Mucore.PEmember_shift _ -> "PEmember_shift"
         | Mucore.PEarray_shift _ -> "PEarray_shift"
         | Mucore.PEcatch_exceptional_condition _ -> "PEcatch_exceptional_condition"
         | Mucore.PEwrapI _ -> "PEwrapI"
         | Mucore.PEmemop _ -> "PEmemop"
         | Mucore.PEnot _ -> "PEnot"
         | Mucore.PEop _ -> "PEop"
         | Mucore.PEconv_int _ -> "PEconv_int"
         | Mucore.PEstruct _ -> "PEstruct"
         | Mucore.PEunion _ -> "PEunion"
         | Mucore.PEcfunction _ -> "PEcfunction"
         | Mucore.PEmemberof _ -> "PEmemberof"
         | Mucore.PEcall _ -> "PEcall"
         | Mucore.PElet _ -> "PElet"
         | Mucore.PEif _ -> "PEif"
         | Mucore.PEare_compatible _ -> "PEare_compatible"
       in
       Printf.eprintf "subst_pexpr: %s\n%!" pe_name
     | _ -> ());
    let pe' =
      match pe with
      | Mucore.PEsym sym -> Mucore.PEsym (subst_sym s sym)
      | Mucore.PEval v -> Mucore.PEval v
      | Mucore.PEconstrained cs ->
        Mucore.PEconstrained cs (* TODO: subst in constraints if needed *)
      | Mucore.PEundef (loc2, ub) -> Mucore.PEundef (loc2, ub)
      | Mucore.PEerror (str, pe1) -> Mucore.PEerror (str, subst_pexpr s pe1)
      | Mucore.PEctor (ctor, pes) -> Mucore.PEctor (ctor, List.map (subst_pexpr s) pes)
      | Mucore.PEmember_shift (pe1, tag, member) ->
        Mucore.PEmember_shift (subst_pexpr s pe1, tag, member)
      | Mucore.PEarray_shift (pe1, ty2, pe2) ->
        Mucore.PEarray_shift (subst_pexpr s pe1, ty2, subst_pexpr s pe2)
      | Mucore.PEcatch_exceptional_condition (it, iop, pe1, pe2) ->
        Mucore.PEcatch_exceptional_condition
          (it, iop, subst_pexpr s pe1, subst_pexpr s pe2)
      | Mucore.PEwrapI (it, iop, pe1, pe2) ->
        Mucore.PEwrapI (it, iop, subst_pexpr s pe1, subst_pexpr s pe2)
      | Mucore.PEmemop (memop, pe1) -> Mucore.PEmemop (memop, subst_pexpr s pe1)
      | Mucore.PEnot pe1 -> Mucore.PEnot (subst_pexpr s pe1)
      | Mucore.PEop (op, pe1, pe2) ->
        Mucore.PEop (op, subst_pexpr s pe1, subst_pexpr s pe2)
      | Mucore.PEconv_int (pe1, pe2) ->
        Mucore.PEconv_int (subst_pexpr s pe1, subst_pexpr s pe2)
      | Mucore.PEstruct (tag, fields) ->
        Mucore.PEstruct (tag, List.map (fun (id, pe1) -> (id, subst_pexpr s pe1)) fields)
      | Mucore.PEunion (tag, id, pe1) -> Mucore.PEunion (tag, id, subst_pexpr s pe1)
      | Mucore.PEcfunction pe1 -> Mucore.PEcfunction (subst_pexpr s pe1)
      | Mucore.PEmemberof (tag, member, pe1) ->
        Mucore.PEmemberof (tag, member, subst_pexpr s pe1)
      | Mucore.PEcall (name, pes) -> Mucore.PEcall (name, List.map (subst_pexpr s) pes)
      | Mucore.PElet (pat, pe1, pe2) ->
        Mucore.PElet (pat, subst_pexpr s pe1, subst_pexpr s pe2)
      | Mucore.PEif (pe1, pe2, pe3) ->
        Mucore.PEif (subst_pexpr s pe1, subst_pexpr s pe2, subst_pexpr s pe3)
      | Mucore.PEare_compatible (pe1, pe2) ->
        Mucore.PEare_compatible (subst_pexpr s pe1, subst_pexpr s pe2)
    in
    Mucore.Pexpr (loc, annots, ty, pe')


  (* Substitute in expr *)
  let rec subst_expr (s : rename_subst) (Mucore.Expr (loc, annots, ty, e))
    : 'ty Mucore.expr
    =
    let e' =
      match e with
      | Mucore.Epure pe -> Mucore.Epure (subst_pexpr s pe)
      | Mucore.Ememop (memop, pes) -> Mucore.Ememop (memop, List.map (subst_pexpr s) pes)
      | Mucore.Eaction pact -> Mucore.Eaction pact (* Skip - complex *)
      | Mucore.Eskip -> Mucore.Eskip
      | Mucore.Eccall (act, pe1, pes, opt) ->
        Mucore.Eccall (act, subst_pexpr s pe1, List.map (subst_pexpr s) pes, opt)
      | Mucore.Eproc (name, pes) -> Mucore.Eproc (name, List.map (subst_pexpr s) pes)
      | Mucore.Elet (pat, pe, e1) -> Mucore.Elet (pat, subst_pexpr s pe, subst_expr s e1)
      | Mucore.Eunseq es -> Mucore.Eunseq (List.map (subst_expr s) es)
      | Mucore.Ewseq (pat, e1, e2) -> Mucore.Ewseq (pat, subst_expr s e1, subst_expr s e2)
      | Mucore.Esseq (pat, e1, e2) -> Mucore.Esseq (pat, subst_expr s e1, subst_expr s e2)
      | Mucore.Eif (pe, e1, e2) ->
        Mucore.Eif (subst_pexpr s pe, subst_expr s e1, subst_expr s e2)
      | Mucore.Ebound e1 -> Mucore.Ebound (subst_expr s e1)
      | Mucore.End es -> Mucore.End (List.map (subst_expr s) es)
      | Mucore.Erun (sym, pes) -> Mucore.Erun (sym, List.map (subst_pexpr s) pes)
      | Mucore.CN_progs (stmts, progs) -> Mucore.CN_progs (stmts, progs)
      (* Skip - complex *)
    in
    Mucore.Expr (loc, annots, ty, e')


  (* Apply a list of renames in sequence *)
  let apply_renames_it (s : rename_subst) (it : IT.t) : IT.t =
    List.fold_left
      (fun acc_it (from, to_) -> IT.subst (IT.make_rename ~from ~to_) acc_it)
      it
      s


  let apply_renames_req (s : rename_subst) (re : Request.t) : Request.t =
    List.fold_left
      (fun acc_re (from, to_) -> Req.subst (IT.make_rename ~from ~to_) acc_re)
      re
      s


  let apply_renames_lc (s : rename_subst) (lc : LogicalConstraints.t)
    : LogicalConstraints.t
    =
    List.fold_left
      (fun acc_lc (from, to_) -> LC.subst (IT.make_rename ~from ~to_) acc_lc)
      lc
      s


  (* Substitute in arguments_l *)
  let rec subst_arguments_l (s : rename_subst) (lat : 'i Mucore.arguments_l)
    : 'i Mucore.arguments_l
    =
    match lat with
    | Mucore.Define ((name, it), info, t) ->
      let it' = apply_renames_it s it in
      Mucore.Define ((name, it'), info, subst_arguments_l s t)
    | Mucore.Resource ((name, (re, bt)), info, t) ->
      let re' = apply_renames_req s re in
      Mucore.Resource ((name, (re', bt)), info, subst_arguments_l s t)
    | Mucore.Constraint (lc, info, t) ->
      let lc' = apply_renames_lc s lc in
      Mucore.Constraint (lc', info, subst_arguments_l s t)
    | Mucore.I (expr, labels, rt) ->
      let expr' = subst_expr s expr in
      Mucore.I (expr', labels, rt)


  (* Substitute in arguments *)
  let rec subst_arguments (s : rename_subst) (args : 'i Mucore.arguments)
    : 'i Mucore.arguments
    =
    match args with
    | Mucore.Computational ((name, bt), info, t) ->
      Mucore.Computational ((name, bt), info, subst_arguments s t)
    | Mucore.Ghost ((name, bt), info, t) ->
      Mucore.Ghost ((name, bt), info, subst_arguments s t)
    | Mucore.L lat -> Mucore.L (subst_arguments_l s lat)
end

(** Alpha-rename Mucore arguments with proper substitution *)
let rec rename_mucore_arguments counter (args : 'i Mucore.arguments) : 'i Mucore.arguments
  =
  match args with
  | Mucore.Computational ((name, bt), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    (match Sys.getenv_opt "CN_DEBUG_HASH" with
     | Some "1" ->
       Printf.eprintf
         "Building subst: %s (id %d) -> %s (id %d)\n%!"
         (Sym.pp_string name)
         (Sym.num name)
         (Sym.pp_string new_name)
         (Sym.num new_name)
     | _ -> ());
    let subst = MucoreSubst.make_rename ~from:name ~to_:new_name in
    let t' = MucoreSubst.subst_arguments subst t in
    let t'' = rename_mucore_arguments counter t' in
    Mucore.Computational ((new_name, bt), info, t'')
  | Mucore.Ghost ((name, bt), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    let subst = MucoreSubst.make_rename ~from:name ~to_:new_name in
    let t' = MucoreSubst.subst_arguments subst t in
    let t'' = rename_mucore_arguments counter t' in
    Mucore.Ghost ((new_name, bt), info, t'')
  | Mucore.L lat -> Mucore.L (rename_mucore_arguments_l counter lat)


and rename_mucore_arguments_l counter (lat : 'i Mucore.arguments_l)
  : 'i Mucore.arguments_l
  =
  match lat with
  | Mucore.Define ((name, it), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    (* For Define, we DO substitute in the term because IT.subst works *)
    let subst = IT.make_rename ~from:name ~to_:new_name in
    let it' = IT.subst subst it in
    (* But we need to apply subst to the rest of the arguments_l too *)
    let rec apply_subst_lat s (lat_inner : 'i Mucore.arguments_l) : 'i Mucore.arguments_l =
      match lat_inner with
      | Mucore.Define ((n, i), inf, rest) ->
        Mucore.Define ((n, IT.subst s i), inf, apply_subst_lat s rest)
      | Mucore.Resource ((n, (re, b)), inf, rest) ->
        Mucore.Resource ((n, (Req.subst s re, b)), inf, apply_subst_lat s rest)
      | Mucore.Constraint (lc, inf, rest) ->
        Mucore.Constraint (LC.subst s lc, inf, apply_subst_lat s rest)
      | Mucore.I i -> Mucore.I i
    in
    let t' = apply_subst_lat subst t in
    let t'' = rename_mucore_arguments_l counter t' in
    Mucore.Define ((new_name, it'), info, t'')
  | Mucore.Resource ((name, (re, bt)), info, t) ->
    let new_name = Sym.fresh (Printf.sprintf "v_%d" !counter) in
    counter := !counter + 1;
    let subst = IT.make_rename ~from:name ~to_:new_name in
    let re' = Req.subst subst re in
    (* Apply subst to rest *)
    let rec apply_subst_lat s (lat_inner : 'i Mucore.arguments_l) : 'i Mucore.arguments_l =
      match lat_inner with
      | Mucore.Define ((n, i), inf, rest) ->
        Mucore.Define ((n, IT.subst s i), inf, apply_subst_lat s rest)
      | Mucore.Resource ((n, (req, b)), inf, rest) ->
        Mucore.Resource ((n, (Req.subst s req, b)), inf, apply_subst_lat s rest)
      | Mucore.Constraint (lc, inf, rest) ->
        Mucore.Constraint (LC.subst s lc, inf, apply_subst_lat s rest)
      | Mucore.I i -> Mucore.I i
    in
    let t' = apply_subst_lat subst t in
    let t'' = rename_mucore_arguments_l counter t' in
    Mucore.Resource ((new_name, (re', bt)), info, t'')
  | Mucore.Constraint (lc, info, t) ->
    let t' = rename_mucore_arguments_l counter t in
    Mucore.Constraint (lc, info, t')
  | Mucore.I i -> Mucore.I i


(** Canonicalize symbols by ID for deterministic hashing.
    Maps each symbol ID to a canonical number based on order of first appearance,
    then creates new symbols with SD_CN_Id. *)
let rename_args_and_body (args_and_body : BT.t Mucore.args_and_body)
  : BT.t Mucore.args_and_body
  =
  (* Track mappings *)
  let counter = ref 0 in
  (* Maps from original symbol to canonical symbol *)
  let symbol_map = Hashtbl.create 100 in
  (* Get or create canonical symbol for a given symbol *)
  let canonicalize_symbol sym =
    match Hashtbl.find_opt symbol_map sym with
    | Some canon_sym -> canon_sym
    | None ->
      let canon_sym = Sym.fresh (Printf.sprintf "s_%d" !counter) in
      incr counter;
      Hashtbl.add symbol_map sym canon_sym;
      (match Sys.getenv_opt "CN_DEBUG_HASH" with
       | Some "1" ->
         Printf.eprintf
           "Canonicalize: %s (id %d) -> s_%d\n%!"
           (Sym.pp_string sym)
           (Sym.num sym)
           (!counter - 1)
       | _ -> ());
      canon_sym
  in
  (* Build substitution for IT.subst *)
  let build_it_subst () : [ `Term of IT.t | `Rename of Sym.t ] Subst.t =
    let assoc =
      Hashtbl.fold
        (fun orig_sym canon_sym acc ->
           (orig_sym, (`Rename canon_sym : [ `Term of IT.t | `Rename of Sym.t ])) :: acc)
        symbol_map
        []
    in
    Subst.make
      (function `Term t -> IT.free_vars t | `Rename s -> Sym.Set.singleton s)
      assoc
  in
  (* Now traverse and replace all symbols *)
  let rec rename_arguments = function
    | Mucore.Computational ((sym, bt), info, rest) ->
      let new_sym = canonicalize_symbol sym in
      Mucore.Computational ((new_sym, bt), info, rename_arguments rest)
    | Mucore.Ghost ((sym, bt), info, rest) ->
      let new_sym = canonicalize_symbol sym in
      Mucore.Ghost ((new_sym, bt), info, rename_arguments rest)
    | Mucore.L lat -> Mucore.L (rename_arguments_l lat)
  and rename_arguments_l = function
    | Mucore.Define ((sym, it), info, rest) ->
      let new_sym = canonicalize_symbol sym in
      let it' = rename_it it in
      Mucore.Define ((new_sym, it'), info, rename_arguments_l rest)
    | Mucore.Resource ((sym, (req, bt)), info, rest) ->
      let new_sym = canonicalize_symbol sym in
      let req' = rename_request req in
      Mucore.Resource ((new_sym, (req', bt)), info, rename_arguments_l rest)
    | Mucore.Constraint (lc, info, rest) ->
      let lc' = rename_lc lc in
      Mucore.Constraint (lc', info, rename_arguments_l rest)
    | Mucore.I (expr, labels, rt) ->
      let expr' = rename_expr expr in
      (* Rename symbols in loop labels - loop invariants contain symbols *)
      let labels' =
        Pmap.map
          (fun label_def ->
             match label_def with
             | Mucore.Loop (loc, loop_args, annots, label_spec, info) ->
               (* Loop invariants are in loop_args arguments structure.
             Since loop_args has type 'TY expr arguments (where the body is expr),
             we need a specialized traversal that handles the expr-typed body. *)
               let rec rename_loop_args
                 : 'ty Mucore.expr Mucore.arguments -> 'ty Mucore.expr Mucore.arguments
                 = function
                 | Mucore.Computational ((sym, bt), info2, rest) ->
                   let sym' = canonicalize_symbol sym in
                   Mucore.Computational ((sym', bt), info2, rename_loop_args rest)
                 | Mucore.Ghost ((sym, bt), info2, rest) ->
                   let sym' = canonicalize_symbol sym in
                   Mucore.Ghost ((sym', bt), info2, rename_loop_args rest)
                 | Mucore.L lat -> Mucore.L (rename_loop_arguments_l lat)
               and rename_loop_arguments_l
                 : 'ty Mucore.expr Mucore.arguments_l ->
                 'ty Mucore.expr Mucore.arguments_l
                 = function
                 | Mucore.Define ((sym, it), info2, rest) ->
                   let sym' = canonicalize_symbol sym in
                   let it' = rename_it it in
                   Mucore.Define ((sym', it'), info2, rename_loop_arguments_l rest)
                 | Mucore.Resource ((sym, (req, bt)), info2, rest) ->
                   let sym' = canonicalize_symbol sym in
                   let req' = rename_request req in
                   Mucore.Resource
                     ((sym', (req', bt)), info2, rename_loop_arguments_l rest)
                 | Mucore.Constraint (lc, info2, rest) ->
                   let lc' = rename_lc lc in
                   Mucore.Constraint (lc', info2, rename_loop_arguments_l rest)
                 | Mucore.I body_expr ->
                   (* The body is just an expr for loop invariants *)
                   let body_expr' = rename_expr body_expr in
                   Mucore.I body_expr'
               in
               let loop_args' = rename_loop_args loop_args in
               Mucore.Loop (loc, loop_args', annots, label_spec, info)
             | Mucore.Non_inlined _ | Mucore.Return _ -> label_def)
          labels
      in
      let rt' = rename_return_type rt in
      Mucore.I (expr', labels', rt')
  and rename_it it =
    (* Walk the term to ensure all symbols are registered, then apply IT.subst.
       IT.subst handles the recursive traversal and substitution. *)
    let rec collect_syms (IT.IT (t, _, _)) =
      match t with
      | Terms.Sym s -> ignore (canonicalize_symbol s)
      | Terms.EachI ((_, (s, _), _), t1) ->
        ignore (canonicalize_symbol s);
        collect_syms t1
      | _ -> () (* IT.subst will handle traversing into subterms *)
    in
    collect_syms it;
    (* Now use IT.subst which will handle the full traversal and substitution *)
    IT.subst (build_it_subst ()) it
  (* Helper to rename Cnprog.t with IndexTerms payload *)
  and rename_cnprog_it (prog : IT.t Cnprog.t) : IT.t Cnprog.t =
    let rec aux = function
      | Cnprog.Let (loc, (sym, load), rest) ->
        let sym' = canonicalize_symbol sym in
        let pointer' = rename_it load.Cnprog.pointer in
        let rest' = aux rest in
        Cnprog.Let (loc, (sym', { load with Cnprog.pointer = pointer' }), rest')
      | Cnprog.Pure (loc, it) -> Cnprog.Pure (loc, rename_it it)
    in
    aux prog
  (* Helper to rename Cnprog.t with Cnstatement.statement payload *)
  and rename_cnprog_stmt (prog : Cnstatement.statement Cnprog.t)
    : Cnstatement.statement Cnprog.t
    =
    let rec aux = function
      | Cnprog.Let (loc, (sym, load), rest) ->
        let sym' = canonicalize_symbol sym in
        let pointer' = rename_it load.Cnprog.pointer in
        let rest' = aux rest in
        Cnprog.Let (loc, (sym', { load with Cnprog.pointer = pointer' }), rest')
      | Cnprog.Pure (loc, stmt) ->
        (* Use Cnstatement.subst to rename all IT.t and LC.t fields in the statement.
           We need to apply all the renamings we've collected. *)
        let stmt' =
          List.fold_left
            (fun acc_stmt (from_sym, to_sym) ->
               Cnstatement.subst (IT.make_rename ~from:from_sym ~to_:to_sym) acc_stmt)
            stmt
            (Hashtbl.fold (fun k v acc -> (k, v) :: acc) symbol_map [])
        in
        Cnprog.Pure (loc, stmt')
    in
    aux prog
  and rename_request = function
    | Request.P p ->
      Request.P
        { p with pointer = rename_it p.pointer; iargs = List.map rename_it p.iargs }
    | Request.Q qp ->
      let q_sym, q_bt = qp.q in
      let q_sym' = canonicalize_symbol q_sym in
      Request.Q
        { qp with
          pointer = rename_it qp.pointer;
          q = (q_sym', q_bt);
          permission = rename_it qp.permission;
          iargs = List.map rename_it qp.iargs
        }
  and rename_lc = function
    | LC.T it -> LC.T (rename_it it)
    | LC.Forall ((s, bt), it) ->
      let s' = canonicalize_symbol s in
      LC.Forall ((s', bt), rename_it it)
  and rename_return_type (RT.Computational ((sym, bt), info, lrt)) =
    let sym' = canonicalize_symbol sym in
    RT.Computational ((sym', bt), info, rename_logical_return_type lrt)
  and rename_logical_return_type = function
    | LRT.Define ((sym, it), info, rest) ->
      let sym' = canonicalize_symbol sym in
      let it' = rename_it it in
      LRT.Define ((sym', it'), info, rename_logical_return_type rest)
    | LRT.Resource ((sym, (req, bt)), info, rest) ->
      let sym' = canonicalize_symbol sym in
      let req' = rename_request req in
      LRT.Resource ((sym', (req', bt)), info, rename_logical_return_type rest)
    | LRT.Constraint (lc, info, rest) ->
      let lc' = rename_lc lc in
      LRT.Constraint (lc', info, rename_logical_return_type rest)
    | LRT.I -> LRT.I
  and rename_paction (Mucore.Paction (p, act)) =
    let act' = rename_action act in
    Mucore.Paction (p, act')
  and rename_action (Mucore.Action (loc, act)) =
    let open Mucore in
    let act' =
      match act with
      | Create (pe1, actype, sym_opt) -> Create (rename_pexpr pe1, actype, sym_opt)
      | CreateReadOnly (pe1, actype, pe2, sym_opt) ->
        CreateReadOnly (rename_pexpr pe1, actype, rename_pexpr pe2, sym_opt)
      | Alloc (pe1, pe2, sym_opt) -> Alloc (rename_pexpr pe1, rename_pexpr pe2, sym_opt)
      | Kill (kind, pe) -> Kill (kind, rename_pexpr pe)
      | Store (is_locking, actype, pe1, pe2, mo) ->
        Store (is_locking, actype, rename_pexpr pe1, rename_pexpr pe2, mo)
      | Load (actype, pe, mo) -> Load (actype, rename_pexpr pe, mo)
      | RMW (actype, pe1, pe2, pe3, mo1, mo2) ->
        RMW (actype, rename_pexpr pe1, rename_pexpr pe2, rename_pexpr pe3, mo1, mo2)
      | Fence mo -> Fence mo
      | CompareExchangeStrong (actype, pe1, pe2, pe3, mo1, mo2) ->
        CompareExchangeStrong
          (actype, rename_pexpr pe1, rename_pexpr pe2, rename_pexpr pe3, mo1, mo2)
      | CompareExchangeWeak (actype, pe1, pe2, pe3, mo1, mo2) ->
        CompareExchangeWeak
          (actype, rename_pexpr pe1, rename_pexpr pe2, rename_pexpr pe3, mo1, mo2)
      | LinuxFence mo -> LinuxFence mo
      | LinuxStore (actype, pe1, pe2, mo) ->
        LinuxStore (actype, rename_pexpr pe1, rename_pexpr pe2, mo)
      | LinuxLoad (actype, pe, mo) -> LinuxLoad (actype, rename_pexpr pe, mo)
      | LinuxRMW (actype, pe1, pe2, mo) ->
        LinuxRMW (actype, rename_pexpr pe1, rename_pexpr pe2, mo)
    in
    Mucore.Action (loc, act')
  and rename_expr (Mucore.Expr (loc, annots, ty, e)) =
    let e' =
      match e with
      | Mucore.Epure pe -> Mucore.Epure (rename_pexpr pe)
      | Mucore.Ememop (memop, pes) ->
        (* Skip memop for now - it's complex Cerberus type *)
        Mucore.Ememop (memop, List.map rename_pexpr pes)
      | Mucore.Eaction pact -> Mucore.Eaction (rename_paction pact)
      | Mucore.Eskip -> Mucore.Eskip
      | Mucore.Eccall (act, pe, pes, opt) ->
        let opt' =
          match opt with
          | None -> None
          | Some (loc, ghost_progs) ->
            (* Rename IndexTerms in ghost argument programs *)
            let ghost_progs' = List.map rename_cnprog_it ghost_progs in
            Some (loc, ghost_progs')
        in
        Mucore.Eccall (act, rename_pexpr pe, List.map rename_pexpr pes, opt')
      | Mucore.Eproc (name, pes) -> Mucore.Eproc (name, List.map rename_pexpr pes)
      | Mucore.Elet (pat, pe, e1) ->
        Mucore.Elet (rename_pattern pat, rename_pexpr pe, rename_expr e1)
      | Mucore.Eunseq es -> Mucore.Eunseq (List.map rename_expr es)
      | Mucore.Ewseq (pat, e1, e2) ->
        Mucore.Ewseq (rename_pattern pat, rename_expr e1, rename_expr e2)
      | Mucore.Esseq (pat, e1, e2) ->
        Mucore.Esseq (rename_pattern pat, rename_expr e1, rename_expr e2)
      | Mucore.Eif (pe, e1, e2) ->
        Mucore.Eif (rename_pexpr pe, rename_expr e1, rename_expr e2)
      | Mucore.Ebound e1 -> Mucore.Ebound (rename_expr e1)
      | Mucore.End es -> Mucore.End (List.map rename_expr es)
      | Mucore.Erun (sym, pes) ->
        Mucore.Erun (canonicalize_symbol sym, List.map rename_pexpr pes)
      | Mucore.CN_progs (stmts, progs) ->
        (* Rename symbols in CN statement programs *)
        let progs' = List.map rename_cnprog_stmt progs in
        Mucore.CN_progs (stmts, progs')
    in
    Mucore.Expr (loc, annots, ty, e')
  and rename_pexpr (Mucore.Pexpr (loc, annots, ty, pe)) =
    let pe' =
      match pe with
      | Mucore.PEsym sym ->
        (match Sys.getenv_opt "CN_DEBUG_HASH" with
         | Some "1" ->
           Printf.eprintf
             "rename_pexpr PEsym: %s (id %d)\n%!"
             (Sym.pp_string sym)
             (Sym.num sym)
         | _ -> ());
        Mucore.PEsym (canonicalize_symbol sym)
      | Mucore.PEval v -> Mucore.PEval v
      | Mucore.PEconstrained cs -> Mucore.PEconstrained cs
      | Mucore.PEundef (loc2, ub) -> Mucore.PEundef (loc2, ub)
      | Mucore.PEerror (str, pe1) -> Mucore.PEerror (str, rename_pexpr pe1)
      | Mucore.PEctor (ctor, pes) -> Mucore.PEctor (ctor, List.map rename_pexpr pes)
      | Mucore.PEmember_shift (pe1, tag, member) ->
        Mucore.PEmember_shift (rename_pexpr pe1, tag, member)
      | Mucore.PEarray_shift (pe1, ty2, pe2) ->
        Mucore.PEarray_shift (rename_pexpr pe1, ty2, rename_pexpr pe2)
      | Mucore.PEcatch_exceptional_condition (it, iop, pe1, pe2) ->
        Mucore.PEcatch_exceptional_condition (it, iop, rename_pexpr pe1, rename_pexpr pe2)
      | Mucore.PEwrapI (it, iop, pe1, pe2) ->
        Mucore.PEwrapI (it, iop, rename_pexpr pe1, rename_pexpr pe2)
      | Mucore.PEmemop (memop, pe1) -> Mucore.PEmemop (memop, rename_pexpr pe1)
      | Mucore.PEnot pe1 -> Mucore.PEnot (rename_pexpr pe1)
      | Mucore.PEop (op, pe1, pe2) -> Mucore.PEop (op, rename_pexpr pe1, rename_pexpr pe2)
      | Mucore.PEconv_int (pe1, pe2) ->
        Mucore.PEconv_int (rename_pexpr pe1, rename_pexpr pe2)
      | Mucore.PEstruct (tag, fields) ->
        Mucore.PEstruct (tag, List.map (fun (id, pe1) -> (id, rename_pexpr pe1)) fields)
      | Mucore.PEunion (tag, id, pe1) -> Mucore.PEunion (tag, id, rename_pexpr pe1)
      | Mucore.PEcfunction pe1 -> Mucore.PEcfunction (rename_pexpr pe1)
      | Mucore.PEmemberof (tag, member, pe1) ->
        Mucore.PEmemberof (tag, member, rename_pexpr pe1)
      | Mucore.PEcall (name, pes) -> Mucore.PEcall (name, List.map rename_pexpr pes)
      | Mucore.PElet (pat, pe1, pe2) ->
        Mucore.PElet (rename_pattern pat, rename_pexpr pe1, rename_pexpr pe2)
      | Mucore.PEif (pe1, pe2, pe3) ->
        Mucore.PEif (rename_pexpr pe1, rename_pexpr pe2, rename_pexpr pe3)
      | Mucore.PEare_compatible (pe1, pe2) ->
        Mucore.PEare_compatible (rename_pexpr pe1, rename_pexpr pe2)
    in
    Mucore.Pexpr (loc, annots, ty, pe')
  and rename_pattern (Mucore.Pattern (loc, annots, ty, p)) =
    let p' =
      match p with
      | Mucore.CaseBase (Some sym, cbt) ->
        Mucore.CaseBase (Some (canonicalize_symbol sym), cbt)
      | Mucore.CaseBase (None, cbt) -> Mucore.CaseBase (None, cbt)
      | Mucore.CaseCtor (ctor, pats) ->
        Mucore.CaseCtor (ctor, List.map rename_pattern pats)
    in
    Mucore.Pattern (loc, annots, ty, p')
  in
  rename_arguments args_and_body
