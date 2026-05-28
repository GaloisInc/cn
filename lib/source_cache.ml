(* Cache source file contents to prevent stale content in error messages
   when files are edited during verification *)

let cache : (string, string) Hashtbl.t = Hashtbl.create 10

let store filename content = Hashtbl.replace cache filename content

let lookup filename = Hashtbl.find_opt cache filename

let clear () = Hashtbl.clear cache
