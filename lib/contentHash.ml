(** Content-based hashing of CN definitions with alpha-renaming normalization

    Uses alpha-renaming to normalize CN-generated variable names while preserving
    user-written names. This enables content-based caching where semantically
    equivalent definitions hash to the same value.
 *)

module BT = BaseTypes
module IT = IndexTerms
module LAT = LogicalArgumentTypes
module Sym_map = Map.Make (Sym)

(** Convert a PPrint document to string with fixed width for deterministic hashing.
    Uses a large fixed width to prevent line wrapping from varying based on terminal size. *)
let pp_to_string (doc : PPrint.document) : string =
  let buffer = Buffer.create 4096 in
  PPrint.ToBuffer.pretty 1.0 1000000 buffer doc;
  Buffer.contents buffer


(** Check if a symbol name looks CN-generated (contains underscore followed by digits) *)
let is_generated_sym (sym : Sym.t) : bool =
  let name = Sym.pp_string sym in
  (* Matches patterns like: i_1234, tmp_5678, v_9012, etc. *)
  Str.string_match (Str.regexp "^[a-zA-Z_][a-zA-Z0-9_]*_[0-9]+$") name 0


(** Normalization context tracks variable renamings *)
type norm_ctx =
  { renaming : Sym.t Sym_map.t;
    (* Map from original to canonical *)
    type_counters : (BT.t, int) Hashtbl.t (* Counter per type for ordering *)
  }

let empty_ctx () = { renaming = Sym_map.empty; type_counters = Hashtbl.create 20 }

(** Generate canonical name for a variable based on type and order *)
let canonical_sym (bt : BT.t) (order : int) (_loc : Locations.t) : Sym.t =
  let type_prefix =
    match bt with
    | BT.Bool -> "bool"
    | BT.Integer -> "int"
    | BT.Bits (_, w) -> Printf.sprintf "bv%d" w
    | BT.Real -> "real"
    | BT.Loc _ -> "loc"
    | BT.Alloc_id -> "alloc"
    | BT.CType -> "ctype"
    | BT.Unit -> "unit"
    | BT.Struct tag -> "struct_" ^ Sym.pp_string tag
    | BT.Datatype tag -> "dt_" ^ Sym.pp_string tag
    | BT.Record _ -> "record"
    | BT.Tuple _ -> "tuple"
    | BT.Map _ -> "map"
    | BT.List _ -> "list"
    | BT.Set _ -> "set"
    | BT.Option _ -> "option"
    | BT.MemByte -> "membyte"
  in
  Sym.fresh (Printf.sprintf "v_%s_%d" type_prefix order)


(** Get or create canonical name for a symbol *)
let get_canonical (ctx : norm_ctx) (sym : Sym.t) (bt : BT.t) (loc : Locations.t)
  : Sym.t * norm_ctx
  =
  if not (is_generated_sym sym) then (* User-written variable, keep as-is *)
    (sym, ctx)
  else (
    match Sym_map.find_opt sym ctx.renaming with
    | Some canonical -> (canonical, ctx)
    | None ->
      (* Generate new canonical name *)
      let count =
        match Hashtbl.find_opt ctx.type_counters bt with Some n -> n | None -> 0
      in
      Hashtbl.replace ctx.type_counters bt (count + 1);
      let canonical = canonical_sym bt count loc in
      let new_renaming = Sym_map.add sym canonical ctx.renaming in
      (canonical, { ctx with renaming = new_renaming }))


(** Normalize an index term by alpha-renaming generated variables *)
let rec normalize_it (ctx : norm_ctx) (it : IT.t) : IT.t * norm_ctx =
  let (IT (term, bt, loc)) = it in
  let term', ctx' =
    match term with
    | Terms.Const _ -> (term, ctx)
    | Terms.Sym s ->
      let s', ctx' = get_canonical ctx s bt loc in
      (Terms.Sym s', ctx')
    | Terms.Unop (op, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.Unop (op, t'), ctx')
    | Terms.Binop (op, t1, t2) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      (Terms.Binop (op, t1', t2'), ctx2)
    | Terms.ITE (t1, t2, t3) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      let t3', ctx3 = normalize_it ctx2 t3 in
      (Terms.ITE (t1', t2', t3'), ctx3)
    | Terms.EachI ((i_sym, (s, bt_s), info), t) ->
      let s', ctx1 = get_canonical ctx s bt_s loc in
      let t', ctx2 = normalize_it ctx1 t in
      (Terms.EachI ((i_sym, (s', bt_s), info), t'), ctx2)
    | Terms.Tuple ts ->
      let ts', ctx' = normalize_list ctx ts in
      (Terms.Tuple ts', ctx')
    | Terms.NthTuple (n, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.NthTuple (n, t'), ctx')
    | Terms.Struct (tag, members) ->
      let members', ctx' = normalize_members ctx members in
      (Terms.Struct (tag, members'), ctx')
    | Terms.StructMember (t, member) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.StructMember (t', member), ctx')
    | Terms.StructUpdate ((t1, member), t2) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      (Terms.StructUpdate ((t1', member), t2'), ctx2)
    | Terms.Record members ->
      let members', ctx' = normalize_members ctx members in
      (Terms.Record members', ctx')
    | Terms.RecordMember (t, member) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.RecordMember (t', member), ctx')
    | Terms.RecordUpdate ((t1, member), t2) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      (Terms.RecordUpdate ((t1', member), t2'), ctx2)
    | Terms.Cast (cbt, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.Cast (cbt, t'), ctx')
    | Terms.MemberShift (t, tag, id) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.MemberShift (t', tag, id), ctx')
    | Terms.ArrayShift { base; ct; index } ->
      let base', ctx1 = normalize_it ctx base in
      let index', ctx2 = normalize_it ctx1 index in
      (Terms.ArrayShift { base = base'; ct; index = index' }, ctx2)
    | Terms.CopyAllocId { addr; loc = loc_t } ->
      let addr', ctx1 = normalize_it ctx addr in
      let loc', ctx2 = normalize_it ctx1 loc_t in
      (Terms.CopyAllocId { addr = addr'; loc = loc' }, ctx2)
    | Terms.HasAllocId loc_t ->
      let loc', ctx' = normalize_it ctx loc_t in
      (Terms.HasAllocId loc', ctx')
    | Terms.SizeOf _ | Terms.OffsetOf _ | Terms.Nil _ -> (term, ctx)
    | Terms.Cons (t1, t2) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      (Terms.Cons (t1', t2'), ctx2)
    | Terms.Head t ->
      let t', ctx' = normalize_it ctx t in
      (Terms.Head t', ctx')
    | Terms.Tail t ->
      let t', ctx' = normalize_it ctx t in
      (Terms.Tail t', ctx')
    | Terms.Representable (sct, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.Representable (sct, t'), ctx')
    | Terms.Good (sct, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.Good (sct, t'), ctx')
    | Terms.WrapI (ity, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.WrapI (ity, t'), ctx')
    | Terms.Aligned { t; align } ->
      let t', ctx1 = normalize_it ctx t in
      let align', ctx2 = normalize_it ctx1 align in
      (Terms.Aligned { t = t'; align = align' }, ctx2)
    | Terms.MapConst (bt_m, t) ->
      let t', ctx' = normalize_it ctx t in
      (Terms.MapConst (bt_m, t'), ctx')
    | Terms.MapSet (t1, t2, t3) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      let t3', ctx3 = normalize_it ctx2 t3 in
      (Terms.MapSet (t1', t2', t3'), ctx3)
    | Terms.MapGet (t1, t2) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let t2', ctx2 = normalize_it ctx1 t2 in
      (Terms.MapGet (t1', t2'), ctx2)
    | Terms.MapDef ((s, bt_s), t) ->
      let s', ctx1 = get_canonical ctx s bt_s loc in
      let t', ctx2 = normalize_it ctx1 t in
      (Terms.MapDef ((s', bt_s), t'), ctx2)
    | Terms.Apply (pred, ts) ->
      let ts', ctx' = normalize_list ctx ts in
      (Terms.Apply (pred, ts'), ctx')
    | Terms.Let ((nm, t1), t2) ->
      let t1', ctx1 = normalize_it ctx t1 in
      let nm', ctx2 = get_canonical ctx1 nm (IT.get_bt t1) loc in
      let t2', ctx3 = normalize_it ctx2 t2 in
      (Terms.Let ((nm', t1'), t2'), ctx3)
    | Terms.Match (t, cases) ->
      let t', ctx1 = normalize_it ctx t in
      let cases', ctx2 = normalize_cases ctx1 cases in
      (Terms.Match (t', cases'), ctx2)
    | Terms.Constructor (ctor, args) ->
      let args', ctx' = normalize_members ctx args in
      (Terms.Constructor (ctor, args'), ctx')
    | Terms.CN_None _ -> (term, ctx)
    | Terms.CN_Some t ->
      let t', ctx' = normalize_it ctx t in
      (Terms.CN_Some t', ctx')
    | Terms.IsSome t ->
      let t', ctx' = normalize_it ctx t in
      (Terms.IsSome t', ctx')
    | Terms.GetOpt t ->
      let t', ctx' = normalize_it ctx t in
      (Terms.GetOpt t', ctx')
  in
  (IT (term', bt, loc), ctx')


and normalize_list ctx ts =
  List.fold_left
    (fun (acc, ctx) t ->
       let t', ctx' = normalize_it ctx t in
       (t' :: acc, ctx'))
    ([], ctx)
    ts
  |> fun (ts, ctx) -> (List.rev ts, ctx)


and normalize_members ctx members =
  List.fold_left
    (fun (acc, ctx) (id, t) ->
       let t', ctx' = normalize_it ctx t in
       ((id, t') :: acc, ctx'))
    ([], ctx)
    members
  |> fun (ms, ctx) -> (List.rev ms, ctx)


and normalize_cases ctx cases =
  List.fold_left
    (fun (acc, ctx) (pat, t) ->
       (* Pattern binding creates new scope *)
       let pat', ctx1 = normalize_pattern ctx pat in
       let t', ctx2 = normalize_it ctx1 t in
       ((pat', t') :: acc, ctx2))
    ([], ctx)
    cases
  |> fun (cs, ctx) -> (List.rev cs, ctx)


and normalize_pattern ctx (Terms.Pat (pat_, bt, loc)) =
  let pat'', ctx' =
    match pat_ with
    | Terms.PSym s ->
      let s', ctx' = get_canonical ctx s bt loc in
      (Terms.PSym s', ctx')
    | Terms.PWild -> (Terms.PWild, ctx)
    | Terms.PConstructor (ctor, args) ->
      let args', ctx' =
        List.fold_left
          (fun (acc, ctx) (id, pat) ->
             let pat', ctx' = normalize_pattern ctx pat in
             ((id, pat') :: acc, ctx'))
          ([], ctx)
          args
      in
      (Terms.PConstructor (ctor, List.rev args'), ctx')
  in
  (Terms.Pat (pat'', bt, loc), ctx')


(** Hash an index term with alpha-renaming normalization *)
let hash_index_term (it : IndexTerms.t) : string =
  let ctx = empty_ctx () in
  let it_norm, _ = normalize_it ctx it in
  let str = pp_to_string (IT.pp it_norm) in
  Digest.string str |> Digest.to_hex


(** Hash a logical function definition *)
let hash_logical_function (def : Definition.Function.t) : string =
  let ctx = empty_ctx () in
  let body_str =
    match def.body with
    | Definition.Function.Def it ->
      let it_norm, _ = normalize_it ctx it in
      "def:" ^ pp_to_string (IT.pp it_norm)
    | Definition.Function.Rec_Def it ->
      let it_norm, _ = normalize_it ctx it in
      "rec_def:" ^ pp_to_string (IT.pp it_norm)
    | Definition.Function.Uninterp -> "uninterp"
  in
  (* Include argument types in hash *)
  let args_str =
    List.map (fun (sym, bt) -> Sym.pp_string sym ^ ":" ^ pp_to_string (BT.pp bt)) def.args
    |> String.concat ","
  in
  let combined = args_str ^ "|" ^ body_str in
  Digest.string combined |> Digest.to_hex


(** Hash a predicate definition *)
let hash_predicate (def : Definition.Predicate.t) : string =
  let ctx = empty_ctx () in
  let clauses_str =
    match def.clauses with
    | None -> "no_clauses"
    | Some clauses ->
      (* Hash each clause - include both guard and packing_ft *)
      List.map
        (fun (clause : Definition.Clause.t) ->
           let it_norm, _ = normalize_it ctx clause.guard in
           let guard_str = pp_to_string (IT.pp it_norm) in
           (* Also hash the packing_ft (return type) *)
           let packing_str = pp_to_string (LAT.pp IT.pp clause.packing_ft) in
           "guard:" ^ guard_str ^ ";packing:" ^ packing_str)
        clauses
      |> String.concat "|"
  in
  (* Include argument types *)
  let args_str =
    List.map
      (fun (sym, bt) -> Sym.pp_string sym ^ ":" ^ pp_to_string (BT.pp bt))
      def.iargs
    |> String.concat ","
  in
  let combined = args_str ^ "|" ^ clauses_str in
  Digest.string combined |> Digest.to_hex


(** Hash a struct definition *)
let hash_struct_definition (decl : Memory.struct_decl) : string =
  (* Hash field names, types, and order *)
  let fields_str =
    Memory.member_types decl
    |> List.map (fun (id, ct) -> Id.get_string id ^ ":" ^ pp_to_string (Sctypes.pp ct))
    |> String.concat ","
  in
  Digest.string fields_str |> Digest.to_hex


(** Hash a datatype definition *)
let hash_datatype_definition (dt_info : BT.dt_info) : string =
  (* Hash constructor names and all parameters *)
  let ctors_str = List.map Sym.pp_string dt_info.constrs |> String.concat "," in
  let params_str =
    List.map
      (fun (id, bt) -> Id.get_string id ^ ":" ^ pp_to_string (BT.pp bt))
      dt_info.all_params
    |> String.concat ","
  in
  Digest.string (ctors_str ^ "|" ^ params_str) |> Digest.to_hex


(** Hash just the specification (pre/post) of a function *)
let hash_function_spec (ft_opt : ArgumentTypes.ft option) : string =
  match ft_opt with
  | None -> Digest.string "no_spec" |> Digest.to_hex
  | Some ft ->
    (* We need to traverse the ft structure and normalize all index terms within it.
       For now, use a simpler approach: serialize to string and hash.
       This won't have alpha-renaming yet, but it's better than the stub. *)
    let ft_str = pp_to_string (ArgumentTypes.pp ReturnTypes.pp ft) in
    Digest.string ft_str |> Digest.to_hex


(** Hash args_and_body using location-independent pretty-printing

    We use Pp_mucore.Basic which has show_locations=false, giving us a
    canonical string representation that excludes filenames and line numbers.

    The pretty-printer outputs the complete function structure including:
    - All arguments (computational and ghost)
    - The function body
    - Loop labels and invariants
    - CN specifications

    This is filename-independent and line-number-independent, so identical
    functions in different files will hash the same.
*)
let hash_args_and_body (args_and_body : BT.t Mucore.args_and_body) : string =
  try
    (* Open infix operators for Pp *)
    let open Pp.Infix in
    (* Pretty-print using Basic module which doesn't show locations *)
    let doc =
      Pp_mucore.Basic.pp_arguments
        (fun (body, labels, rt) ->
           (* Print body *)
           Pp_mucore.Basic.pp_expr None body
           (* Include labels (loop invariants etc) *)
           ^^^ Pmap.fold
                 (fun _sym def acc ->
                    acc
                    ^^^
                    match def with
                    | Mucore.Loop (_loc, loop_args, _annots, _label_spec, _info) ->
                      (* Include loop spec which has invariants *)
                      Pp.string "loop_inv"
                      ^^^ Pp_mucore.Basic.pp_arguments (fun _ -> Pp.empty) loop_args
                    | _ -> Pp.empty)
                 labels
                 Pp.empty
           (* Include return type *)
           ^^^ ReturnTypes.pp rt)
        args_and_body
    in
    (* Convert to string with fixed width to ensure deterministic output *)
    let str = pp_to_string doc in
    (* Debug: Print serialized text if environment variable is set *)
    (match Sys.getenv_opt "CN_DEBUG_HASH" with
     | Some "1" ->
       Printf.eprintf "=== Serialized text for hashing ===\n%s\n=== End ===\n%!" str
     | _ -> ());
    (* Hash the string *)
    Digest.string str |> Digest.to_hex
  with
  | exn ->
    (* Don't fall back - fail explicitly so we know about the problem *)
    Printf.eprintf
      "ERROR: Failed to pretty-print function for hashing: %s\n%!"
      (Printexc.to_string exn);
    raise exn


(** Hash a full function definition including spec and body *)
let hash_function
      (_def : Definition.Function.t)
      (ft_opt : ArgumentTypes.ft option)
      (_body : BT.t Mucore.pexpr)
  : string
  =
  (* For now, just hash the spec - body hashing would require Mucore traversal *)
  (* TODO: implement proper body hashing *)
  hash_function_spec ft_opt


(** Hash a lemma definition *)
let hash_lemma (lemma_typ : ArgumentTypes.lemmat) : string =
  (* Similar to hash_function_spec, hash the lemma type *)
  let lemma_str = pp_to_string (ArgumentTypes.pp LogicalReturnTypes.pp lemma_typ) in
  Digest.string lemma_str |> Digest.to_hex
