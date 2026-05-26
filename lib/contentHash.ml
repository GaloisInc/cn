(** Content-based hashing of CN definitions with alpha-renaming normalization

    TODO: This is currently a stub implementation that just uses string hashing.
    A proper implementation would need alpha-renaming normalization like query_cache.ml
 *)

module BT = BaseTypes

(** Hash an index term - stub for now *)
let hash_index_term (_it : IndexTerms.t) : string =
  (* TODO: implement proper normalization and hashing *)
  Digest.string "index_term" |> Digest.to_hex

(** Hash a logical function definition - stub for now *)
let hash_logical_function (def : Definition.Function.t) : string =
  (* For now, just hash the symbol name *)
  let name = match def.body with
    | Definition.Function.Def _ -> "def"
    | Definition.Function.Rec_Def _ -> "rec_def"
    | Definition.Function.Uninterp -> "uninterp"
  in
  Digest.string name |> Digest.to_hex

(** Hash a predicate definition - stub for now *)
let hash_predicate (def : Definition.Predicate.t) : string =
  (* For now, just hash based on whether it has clauses *)
  let has_clauses = Option.is_some def.clauses in
  Digest.string (string_of_bool has_clauses) |> Digest.to_hex

(** Hash a struct definition - stub for now *)
let hash_struct_definition (_decl : Memory.struct_decl) : string =
  (* TODO: hash the actual struct definition *)
  Digest.string "struct" |> Digest.to_hex

(** Hash a datatype definition - stub for now *)
let hash_datatype_definition (_dt_info : BT.dt_info) : string =
  (* TODO: hash the actual datatype definition *)
  Digest.string "datatype" |> Digest.to_hex

(** Hash just the specification (pre/post) of a function - stub for now *)
let hash_function_spec (ft_opt : ArgumentTypes.ft option) : string =
  match ft_opt with
  | None -> Digest.string "no_spec" |> Digest.to_hex
  | Some _ft ->
    (* TODO: hash the actual spec *)
    Digest.string "has_spec" |> Digest.to_hex

(** Hash a full function definition including spec and body - stub for now *)
let hash_function
    (_def : Definition.Function.t)
    (ft_opt : ArgumentTypes.ft option)
    (_body : BT.t Mucore.pexpr)
  : string =
  (* For now, just hash the spec *)
  hash_function_spec ft_opt
