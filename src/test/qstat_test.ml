open Pbs_internal_pervasives

let say fmt =
  ksprintf (fun s -> printf "QStat-test: %s\n%!" s) fmt

let test_parsing () =
  let open Result in
  let fail_test fmt = ksprintf (fun s -> fail (`test_failure s)) fmt in
  let some_status ~id ~status = sprintf "\
Job Id: %s\n\
    Job_Name = The Job Name\n\
    Job_Owner = seb@somecluster.edu\n\
    resources_used.cput = 11:55:55\n\
    resources_used.mem = 514348kb\n\
    resources_used.vmem = 2924268kb\n\
    resources_used.walltime = 01:47:06\n\
    job_state = %s\n\
    queue = some-queue\n\
    server = local_server\n\
    Checkpoint = disabled\n\
    " id status
  in
  let id = "12345.crunch.local"  in
  let s1 = some_status ~id ~status:"R" in
  (* dbg "s1: %S" s1; *)
  Pbs_qstat.parse_qstat s1
  >>= fun qstat ->
  Pbs_qstat.get_status  qstat >>= begin function
  | `running -> return ()
  | other ->
    fail_test "s1, get_status: wrong status: %s"
      (Pbs_qstat.status_to_string_hum other)
  end
  >>= fun () ->
  begin match Pbs_qstat.job_id qstat with
  | s when s = id -> return ()
  | other -> fail_test "s1: wrong job id: %s" other
  end
  >>= fun () ->
  let s2 = some_status ~id ~status:"Q" in
  Pbs_qstat.parse_qstat s2
  >>= fun qstat ->
  Pbs_qstat.get_status  qstat >>= begin function
  | `queued -> return ()
  | other ->
    fail_test "s2, get_status: wrong status: %s"
      (Pbs_qstat.status_to_string_hum other)
  end
  >>= fun () ->
  begin match Pbs_qstat.job_id qstat with
  | s when s = id -> return ()
  | other -> fail_test "s2: wrong job id: %s" other
  end
  >>= fun () ->
  begin match Pbs_qstat.raw_field qstat "queue" with
  | Some "some-queue" -> return ()
  | Some other -> fail_test "s2.queue: %s" other
  | None -> fail_test "s2.queue: not found"
  end
  >>= fun () ->
  begin match Pbs_qstat.raw_field qstat "absence" with
  | Some thing -> fail_test "s2.absence: %s" thing
  | None -> return ()
  end
  >>= fun () ->
  let s3 = some_status ~id ~status:"Q\nROGUE LINE\n" in
  Pbs_qstat.parse_qstat s3
  |> begin function
  | `Ok _ -> fail_test "s3 should not be parsable"
  | `Error (`qstat (`wrong_lines _)) -> return ()
  | `Error (`qstat _) -> fail_test "other error for s3"
  end
  >>= fun () ->
  return ()


let () =
  match test_parsing () with
  | `Ok () -> say "Done."; exit 0
  | `Error e ->
    say "TEST FAILED:\n%s" 
      (match e with
      | `qstat _ as e -> sprintf "QStat error: %s" (Pbs_qstat.error_to_string e)
      | `test_failure s -> sprintf "test_failure: %S" s);
    exit 1
