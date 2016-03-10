
open Pbs_internal_pervasives


module Command = struct

  type t = string

  let of_string (s : string)= (s : t)
  let to_string s = s

end

module Program = struct

  type t =
    | Raw of string
    | Sequence of Command.t list
    | Monitored of string * Command.t list
    | Concat of t * t
    | Array_item of (string -> t)

  let command_sequence tl = Sequence tl

  let monitored_command_sequence ~with_file tl = Monitored (with_file, tl)

  let and_then t t = Concat (t, t)

  let array_item f = Array_item f

  let raw s = Raw s

  let rec to_string = function
  | Raw s -> s
  | Sequence l -> String.concat ~sep:"\n" (List.map l Command.to_string)
  | Concat (t1, t2) ->
    to_string t1 ^ "\n\n" ^ to_string t2
  | Monitored (messages_path, l) ->
    let date_rfc3339 = "date  '+%Y-%m-%d %H:%M:%S.%N%:z'" in
    let cmd_count = ref 0 in
    let checked_command s =
      incr cmd_count;
      sprintf "echo \"Begin: #%d $(%s) @\" %S >> %s\n\
               %s\n\
               return_code=$?\n\
               if [ $return_code -ne 0 ]; then\n\
              \    echo \"Command #%d failed on $(%s) with return code: $return_code @\" %S >> %s\n\
              \    exit $return_code\n\
               fi\n\
               echo \"End: #%d $(%s) @\" %S >> %s\n\
              "
        !cmd_count date_rfc3339 (Command.to_string s) messages_path
        (Command.to_string s)
        !cmd_count date_rfc3339 (Command.to_string s) messages_path
        !cmd_count date_rfc3339 (Command.to_string s) messages_path
    in
    String.concat ~sep:"\n" (List.map l ~f:checked_command)
  | Array_item make -> make "$PBS_ARRAYID" |> to_string

end


type t = {
  header: string list;
  content: Program.t;
}

type emailing = [
  | `Never
  | `Always of string
]
type array_index = [ `Index of int | `Range of int * int ]

type dependency = [
  | `After_ok of string
  | `After_not_ok of string
  | `After of string
]
type timespan = [
  | `Hours of float
]

let create
  ?name
  ?(shell="/bin/bash")
  ?walltime
  ?(email_user: emailing=`Never)
  ?queue
  ?stderr_path
  ?stdout_path
  ?(array_indexes: array_index list option)
  ?(dependencies: dependency list option)
  ?(nodes=1) ?(ppn=1) program =
  let header =
    let resource_list =
      let walltime = match walltime with
        | Some (`Hours h) ->
          let hr = floor (abs_float h)  in
          let min = floor ((abs_float h -. hr) *. 60.) in
          sprintf ",walltime=%02d:%02d:00" (int_of_float hr) (int_of_float min)
        | None -> ""
      in
      sprintf "nodes=%d:ppn=%d%s" nodes ppn walltime in
    let opt o ~f = Option.value_map ~default:[] o ~f:(fun s -> [f s]) in

    List.concat [
      [sprintf "#! %s" shell];
      begin match email_user with
      | `Never -> []
      | `Always email -> ["#PBS -m abe"; sprintf "#PBS -M %s" email]
      end;
      [sprintf "#PBS -l %s" resource_list];
      opt stderr_path ~f:(sprintf "#PBS -e %s");
      opt stdout_path ~f:(sprintf "#PBS -o %s");
      opt name ~f:(sprintf "#PBS -N %s");
      opt queue ~f:(sprintf "#PBS -q %s");
      opt array_indexes ~f:(fun indexes ->
        sprintf "#PBS -t %s"
          (List.map indexes ~f:(function
           | `Index i -> Int.to_string i
           | `Range (l, h) -> sprintf "%d-%d" l h)
           |> String.concat ~sep:","));
      opt dependencies ~f:(fun deps ->
        sprintf "#PBS -W %s"
          (List.map deps ~f:(function
           | `After id -> sprintf "depend=afterany:%s" id
           | `After_ok id -> sprintf "depend=afterok:%s" id
           | `After_not_ok id -> sprintf "depend=afternotok:%s" id)
           |> String.concat ~sep:","));
    ]
  in
  {header; content = program}

let to_string { header; content } =
  String.concat ~sep:"\n" header ^ "\n\n" ^ Program.to_string content ^ "\n"

let make_create how_to ?name ?shell ?walltime ?email_user ?queue
    ?stderr_path ?stdout_path ?array_indexes ?dependencies ?nodes ?ppn arg =
  create ?name ?shell ?walltime ?email_user ?queue ?stderr_path
    ?array_indexes ?stdout_path  ?dependencies ?nodes ?ppn (how_to arg)

let raw =
  make_create (fun s -> Program.(raw s))

let sequence =
  make_create (fun sl ->
    Program.(Command.(command_sequence (List.map sl of_string))))

let monitored_sequence ~with_file =
  make_create (fun sl ->
    Program.(Command.(monitored_command_sequence ~with_file
          (List.map sl of_string))))

let array_sequence =
  make_create (fun f ->
    Program.(Command.(array_item (fun s ->
          f s |> List.map ~f:of_string |> command_sequence))))

