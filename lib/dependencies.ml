(** Shared state for collecting dependencies during type checking *)

(** Thread-local storage for collecting logical function uses during type checking *)
let logical_function_uses : Sym.t list ref = ref []

(** Thread-local storage for collecting lemma uses during type checking *)
let lemma_uses : Sym.t list ref = ref []

(** Record a logical function use (called from typing.ml) *)
let record_logical_function_use (sym : Sym.t) : unit =
  logical_function_uses := sym :: !logical_function_uses


(** Record a lemma use (called from check.ml) *)
let record_lemma_use (sym : Sym.t) : unit = lemma_uses := sym :: !lemma_uses

(** Get all recorded logical function uses *)
let get_logical_function_uses () : Sym.t list = !logical_function_uses

(** Get all recorded lemma uses *)
let get_lemma_uses () : Sym.t list = !lemma_uses

(** Reset the collector (called at start of each function verification) *)
let reset_logical_function_uses () : unit = logical_function_uses := []

(** Reset lemma collector *)
let reset_lemma_uses () : unit = lemma_uses := []
