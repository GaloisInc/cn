(* Simple timing instrumentation for profiling CN overhead *)

let enabled = ref false

type phase_stats =
  { mutable count : int;
    mutable total_time : float
  }

let phases : (string, phase_stats) Hashtbl.t = Hashtbl.create 20

let time_phase name f =
  if !enabled then (
    let t0 = Unix.gettimeofday () in
    let result = f () in
    let t1 = Unix.gettimeofday () in
    let elapsed = t1 -. t0 in
    (match Hashtbl.find_opt phases name with
     | Some stats ->
       stats.count <- stats.count + 1;
       stats.total_time <- stats.total_time +. elapsed
     | None -> Hashtbl.add phases name { count = 1; total_time = elapsed });
    result)
  else
    f ()


let print_stats () =
  if !enabled then (
    Printf.eprintf "\n=== CN Performance Profile ===\n";
    let sorted =
      Hashtbl.fold (fun name stats acc -> (name, stats) :: acc) phases []
      |> List.sort (fun (_, s1) (_, s2) -> Float.compare s2.total_time s1.total_time)
    in
    List.iter
      (fun (name, stats) ->
         let avg = stats.total_time /. float_of_int stats.count in
         Printf.eprintf
           "%-40s: %6d calls, %8.3fs total, %8.3fms avg\n"
           name
           stats.count
           stats.total_time
           (avg *. 1000.0))
      sorted;
    let total = List.fold_left (fun acc (_, s) -> acc +. s.total_time) 0.0 sorted in
    Printf.eprintf "%-40s: %8.3fs\n" "TOTAL" total;
    Printf.eprintf "===============================\n\n")


let reset () = Hashtbl.clear phases
