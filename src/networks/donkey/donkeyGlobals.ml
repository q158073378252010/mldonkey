(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

open Int64ops
open CommonDownloads

open CommonInteractive
open TcpBufferedSocket
open Queues
open Printf2
open Md4
open CommonResult
open CommonFile
open CommonServer
open CommonComplexOptions
open CommonClient
open Options
open CommonTypes
open DonkeyTypes
open BasicSocket
open CommonOptions
open DonkeyOptions
open CommonOptions
open CommonGlobals

      
(*************************************************************

Define the instances of the plugin classes, that we be filled
later with functions defining the specialized methods for this
plugin.
  
**************************************************************)  
  
open CommonNetwork
  
let network = CommonNetwork.new_network "Donkey"
         [ 
    NetworkHasServers; 
    NetworkHasSearch;
    NetworkHasUpload;
    NetworkHasMultinet;
    NetworkHasChat;
  ]

    (fun _ -> !!network_options_prefix)
  (fun _ -> !!commit_in_subdir)
(*    network_options_prefix commit_in_subdir *)
let connection_manager = network.network_connection_manager
let connections_controler = TcpServerSocket.create_connections_contoler
    "Edonkey" (fun _ _ -> true)
  
let (shared_ops : file CommonShared.shared_ops) = 
  CommonShared.new_shared_ops network
      
let (result_ops : result CommonResult.result_ops) = 
  CommonResult.new_result_ops network
  
let (server_ops : server CommonServer.server_ops) = 
  CommonServer.new_server_ops network

let (room_ops : server CommonRoom.room_ops) = 
  CommonRoom.new_room_ops network
  
let (user_ops : user CommonUser.user_ops) = 
  CommonUser.new_user_ops network
  
let (file_ops : file CommonFile.file_ops) = 
  CommonFile.new_file_ops network

let (client_ops : client CommonClient.client_ops) = 
  CommonClient.new_client_ops network

let (pre_shared_ops : file_to_share CommonShared.shared_ops) = 
  CommonShared.new_shared_ops network
    
let (shared_ops : file CommonShared.shared_ops) = 
  CommonShared.new_shared_ops network
  

let client_must_update c =
  client_must_update (as_client c.client_client)

let server_must_update s =
  server_must_update (as_server s.server_server)

let as_client c = as_client c.client_client
let as_file file = as_file file.file_file    
let file_priority file = file.file_file.impl_file_priority
let file_size file = file.file_file.impl_file_size
let file_downloaded file = file_downloaded (as_file file)
let file_age file = file.file_file.impl_file_age
let file_fd file = file.file_file.impl_file_fd
let file_disk_name file = file_disk_name (as_file file)
let file_best_name file = file_best_name (as_file file)
let set_file_disk_name file = set_file_disk_name (as_file file)
  
let client_num c = client_num (as_client c)  
let file_num c = file_num (as_file c)  
let server_num c = server_num (as_server c.server_server)  

        
(*************************************************************

    General useful structures and functions
  
**************************************************************)  

let tag_client = 200
let tag_server = 201
let tag_file   = 202

  (* CONSTANTS *)
let page_size = Int64.of_int 4096    


(* GLOBAL STATE *)
  
open DonkeyMftp

  
let client_to_client_tags = ref ([] : tag list)
let client_to_server_tags = ref ([] : tag list)
let emule_info = 
  let module E = DonkeyProtoClient.EmuleClientInfo in
  {
    E.version = 66; 
    E.protversion = 66;
    E.tags = [];
  }

let client_port = ref 0
let overnet_connectreply_tags = ref ([] :  tag list)
let overnet_connect_tags = ref ([] :  tag list)
let overnet_client_port = ref 0

(* overnet_md4 should be different from client_md4 for protocol safety reasons *)
let overnet_md4 = Md4.random()
(*let overnet_md4 = Md4.of_string "FBB5EA4C0A82FB995911223344556677";*)
    
module H = Weak2.Make(struct
      type t = client
      let hash c = Hashtbl.hash c.client_kind
      
      let equal x y = x.client_kind = y.client_kind
    end)

  
let clients_by_kind = H.create 127
  
  (*
module HS = Weak2.Make(struct
      type t = source
      let hash s = Hashtbl.hash s.source_addr
      
      let equal x y = x.source_addr = y.source_addr
    end)
  
let verbose_sources = verbose_src_manager
let source_counter = ref 0
let stats_new_sources = ref 0
let sources_by_address = HS.create 13557
let stats_sources = ref 0

  
let create_source new_score source_age addr = 
  let ip, port = addr in
  if !verbose_sources then begin
      lprintf "queue_new_source %s:%d\n" (Ip.to_string ip) port; 
    end;
  try
    let finder =  { dummy_source with source_addr = addr } in
    let s = HS.find sources_by_address finder in
    
    incr stats_new_sources;
    s
  
  with _ ->
      let n = CommonClient.book_client_num () in
      let s = { dummy_source with
(*          source_num = (incr source_counter;!source_counter); *)
          source_addr = addr;
          source_age = source_age;
          source_last_score = new_score;
          source_last_age = source_age;
          source_client_num = n;
          source_files = [];
        }  in
      HS.add sources_by_address s;
      incr stats_sources;
      if !verbose_sources then begin
          lprintf "Source %d added\n" n; 
        end;
      s
        *)

(* let clients_by_name = Hashtbl.create 127 *)

let clients_root = ref []

let nservers = ref 0
let servers_by_key = Hashtbl.create 127
let servers_list = ref ([] : server list)
  
(* let remaining_time_for_clients = ref (60 * 15) *)
let location_counter = ref 0

let current_files = ref ([] : file list)
  
let sleeping = ref false
  
let xs_last_search = ref (-1)
let xs_servers_list = ref ([] : server list)
  
let zone_size = Int64.of_int (180 * 1024) 
let block_size = Int64.of_int 9728000
  
let queue_timeout = ref (60. *. 10.) (* 10 minutes *)
    
let files_queries_per_minute = 1
    
let nclients = ref 0
  
let connected_server_list = ref ([]  : server list)

let protocol_version = 61
  
let (banned_ips : (Ip.t, int) Hashtbl.t) = Hashtbl.create 113
let (old_requests : (int * int, request_record) Hashtbl.t) = 
  Hashtbl.create 13013

  
  
let max_file_groups = 1000
let (file_groups_fifo : Md4.t Fifo.t) = Fifo.create ()

    
let (connected_clients : (Md4.t, client) Hashtbl.t) = Hashtbl.create 13

  
let _ =
  network.op_network_connected_servers <- (fun _ ->
      List2.tail_map (fun s -> as_server s.server_server) !connected_server_list   
  )
  
  
let hashtbl_remove table key v = 
  try
    let vv = Hashtbl.find table key in
    if vv == v then 
      Hashtbl.remove table key
  with _ -> ()

let add_connected_server c =
  connected_server_list := c :: !connected_server_list
  
let remove_connected_server c =
  connected_server_list := List2.removeq c !connected_server_list

let connected_servers () = !connected_server_list
  
let udp_sock = ref (None: UdpSocket.t option)
        
let get_udp_sock () =
  match !udp_sock with
    None -> failwith "No UDP socket"
  | Some sock -> sock

  
let listen_sock = ref (None : TcpServerSocket.t option)
  
let reversed_sock = ref (None : TcpServerSocket.t option)


  
let udp_servers_list = ref ([] : server list)
let interesting_clients = ref ([] : client list)
  
  
(* 'NEW' FUNCTIONS *)  
let files_by_md4 = Hashtbl.create 127

let find_file md4 = Hashtbl.find files_by_md4 md4

    
let servers_ini_changed = ref true

let shared_files_info = (Hashtbl.create 127 : (string, shared_file_info) Hashtbl.t)
let new_shared = ref ([] : file list)
let shared_files = ref ([] : file_to_share list)

  
(* compute the name used to save the file *)
  
let update_best_name file =
  
  let md4_name = Md4.to_string file.file_md4 in
  
  if file_best_name file = md4_name then
    try
(*      lprintf "BEST NAME IS MD4 !!!\n";  *)
      let rec good_name file list =
        match list with
          [] -> raise Not_found;
        | (t,_) :: q -> if t <> md4_name then
              (String2.replace t '/' "::") else good_name file q in
      
      set_file_best_name (as_file file) 
      (good_name file file.file_filenames);
     
(*      lprintf "BEST NAME now IS %s" (file_best_name file); *)
    with Not_found -> ()

let new_shared_files = ref [] 
        
let new_file file_state file_name md4 file_size writable =
  lprintf "NEW FILE TO DOWNLOAD ??????????? %s\n" file_name;
  try
    find_file md4 
  with _ ->
      let file_exists = Unix32.file_exists file_name in
      
      let t = 
        if
(* Don't use this for shared files ! *)
          writable && 
(* Only if the option is set *)
          !!emulate_sparsefiles &&
(* Only if the file does not already exists *)
          not (Sys.file_exists file_name)
        then
          Unix32.create_sparsefile file_name
        else
          Unix32.create_diskfile file_name Unix32.rw_flag 0o666
      in
      let file_size =
        if file_size = Int64.zero then
          try
            Unix32.getsize file_name
          with _ ->
              failwith "Zero length file ?"
        else file_size
      in

      if file_size <> zero then
        Unix32.ftruncate64 t file_size;
      
      let nchunks = Int64.to_int (Int64.div 
            (Int64.sub file_size Int64.one) block_size) + 1 in
      let md4s = if file_size <= block_size then
          [md4] 
        else [] in
      let rec file = {
          file_file = file_impl;
          file_shared = None;
(*          file_exists = file_exists; *)
          file_md4 = md4;
          file_swarmer = None;
          file_nchunks = nchunks;

(*          file_chunks = [||]; *)
(*          file_chunks_order = [||]; *)
(*          file_chunks_age = [||]; *)
(*          file_all_chunks = String.make nchunks '0'; *)
(*          file_absent_chunks =   [Int64.zero, file_size]; *)
          file_filenames = [Filename.basename file_name, GuiTypes.noips() ];
(*          file_nsources = 0; *)
          file_md4s = Array.of_list md4s;
(*          file_available_chunks = Array.create nchunks 0; *)
          file_format = FormatNotComputed 0;
(*          file_locations = Intmap.empty; *)
(*          file_mtime = 0.0; *)
(*          file_initialized = false; *)
          
(*          file_clients = Fifo.create (); *)
          file_sources = DonkeySources.create_file_sources_manager
            (Md4.to_string md4) 
        }
      and file_impl = {
          dummy_file_impl with
          impl_file_val = file;
          impl_file_ops = file_ops;
          impl_file_age = last_time ();          
          impl_file_size = file_size;
          impl_file_fd = t;
          impl_file_best_name = Filename.basename file_name;
          impl_file_last_seen = last_time () - 100 * 24 * 3600;
        }
      in
      
      file.file_sources.DonkeySources.manager_file <- (fun () -> as_file file);
      
      (let swarmer = Int64Swarmer.create (as_file file) block_size zone_size
        in
        file.file_swarmer <- Some swarmer;
        Int64Swarmer.set_writer swarmer (fun offset s pos len ->      
(*
      lprintf "DOWNLOADED: %d/%d/%d\n" pos len (String.length s);
      AnyEndian.dump_sub s pos len;
*)
            
            if !!CommonOptions.buffer_writes then 
              Unix32.buffered_write_copy t offset s pos len
            else
              Unix32.write  t offset s pos len
        );
        Int64Swarmer.set_verifier swarmer (fun num begin_pos end_pos ->
            if file.file_md4s = [||] then raise Int64Swarmer.VerifierNotReady;
            lprintf "Md4 to compute: %d %Ld-%Ld\n" num begin_pos end_pos;
            Unix32.flush_fd (file_fd file);
            let md4 = Md4.digest_subfile (file_fd file) 
              begin_pos (end_pos -- begin_pos) in
            let result = md4 = file.file_md4s.(num) in
            lprintf "Md4 computed: %s against %s = %s\n"
              (Md4.to_string md4) 
            (Md4.to_string file.file_md4s.(num))
            (if result then "VERIFIED" else "CORRUPTED");
            if result then begin
                let bitmap = Int64Swarmer.verified_bitmap swarmer in
                try ignore (String.index bitmap '3')
                with _ -> 
                    new_shared_files := file :: !new_shared_files;
                    file_must_update file;
              end;
            result)
        );
        
      update_best_name file;
      file_add file_impl file_state;
      Heap.set_tag file tag_file;
      Hashtbl.add files_by_md4 md4 file;
      file
  
  (*

  for i = 0 to file.file_nchunks - 1 do
    if client_chunks.(i) then 
      let new_n = file.file_available_chunks.(i) + 1 in
      if new_n  < 11 then  file_must_update file;
      file.file_available_chunks.(i) <- new_n;
  done

let remove_client_chunks file client_chunks = 
  for i = 0 to file.file_nchunks - 1 do
    if client_chunks.(i) then
      let new_n = file.file_available_chunks.(i) - 1 in
      if new_n < 11 then file_must_update file;
      file.file_available_chunks.(i) <- new_n;
      client_chunks.(i) <- false  
  done
    *)

let is_black_address ip port =
  !!black_list && (
(* lprintf "is black ="; *)
    not (ip_reachable ip) || (Ip.matches ip !!server_black_list) ||
    (List.mem port !!port_black_list) ||
    (match Ip_set.match_ip !Ip_set.bl ip with
        None -> false
      | Some br ->
          if !verbose_connect then
            lprintf "%s:%d blocked: %s\n" (Ip.to_string ip) port br.Ip_set.blocking_description;
          true))
  
let new_server ip port score = 
  let key = (ip, port) in
  try
    Hashtbl.find servers_by_key key
  with _ ->
      let rec s = { 
        server_server = server_impl;
        server_next_udp = last_time ();
        server_ip = ip;     
        server_cid = None (* client_ip None *);
        server_port = port; 
        server_sock = NoConnection; 
        server_nqueries = 0;
        server_search_queries = Fifo.create ();
        server_users_queries = Fifo.create ();
        server_connection_control = new_connection_control ();
        server_score = score;
        server_tags = [];
        server_nfiles = 0;
        server_nusers = 0;
          server_max_users = 0;
        server_name = "";
        server_description = "";
        server_banner = "";
        server_users = [];
        server_master = false;
        server_mldonkey = false;
        server_last_message = 0;
        server_queries_credit = 0;
        server_waiting_queries = [];
        server_id_requests = Fifo.create ();
          server_flags = 0;
          server_has_zlib = false;
      }
      and server_impl = 
        {
          dummy_server_impl with          
          CommonServer.impl_server_val = s;
          CommonServer.impl_server_ops = server_ops;
        }
      in
      server_add server_impl;
      Heap.set_tag s tag_server;
      Hashtbl.add servers_by_key key s;
      server_must_update s;
      s      

let find_server ip port =
  let key = (ip, port) in
  Hashtbl.find servers_by_key key  

let remove_server ip port =
  let key = (ip, port) in
  let s = Hashtbl.find servers_by_key key in
  try
    Hashtbl.remove servers_by_key key;
    servers_list := List2.removeq s !servers_list ;
    (match s.server_sock with
        NoConnection -> ()
      | ConnectionWaiting token -> cancel_token token
      | Connection sock -> 
          TcpBufferedSocket.shutdown sock Closed_by_user);
    server_remove (as_server s.server_server)
  with _ -> ()

let dummy_client = 
  let module D = DonkeyProtoClient in
  let rec c = {
      client_client = client_impl;
      client_upload = None;
      client_kind = Direct_address (Ip.null, 0);
      client_source = DonkeySources.dummy_source;
(*      client_sock = NoConnection; *)
      client_ip = Ip.null;
      client_md4 = Md4.null;
      client_last_filereqs = 0;
(*      client_chunks = [||]; *)
      client_download = None;
(*      client_block = None; *)
(*      client_zones = []; *)
(*      client_connection_control =  new_connection_control_recent_ok ( ()); *)
      client_file_queue = [];
      client_tags = [];
      client_name = "";
      client_all_files = None;
      client_next_view_files = last_time () - 1;
(*      client_all_chunks = ""; *)
      client_rating = 0;
      client_brand = Brand_unknown;
      client_mod_brand = Brand_mod_unknown;
      client_checked = false;
      client_connected = false;
      client_downloaded = Int64.zero;
      client_uploaded = Int64.zero;
      client_banned = false;
      client_score = 0;
      client_next_queue = 0;
      client_rank = 0;
      client_connect_time = 0;
      client_requests_sent = 0;
      client_requests_received = 0;
      client_indirect_address = None;
      client_slot = SlotNotAsked;
      client_debug = false;
      client_pending_messages = [];
      client_emule_proto = emule_proto ();
      client_comp = None;
      client_connection_time = 0;
      } and
    client_impl = {
      dummy_client_impl with            
      impl_client_val = c;
      impl_client_ops = client_ops;
      impl_client_upload = None;
    }
  in
  c  
    
  
let create_client key =  
  let module D = DonkeyProtoClient in
  let s = DonkeySources.find_source_by_uid key in
  let rec c = {
(*      dummy_client with *)
      
      client_client = client_impl;
(*      client_connection_control =  new_connection_control_recent_ok ( ()); *)
      client_next_view_files = last_time () - 1;
      client_kind = key;   
      client_upload = None;
      client_source = s;
(*      client_sock = NoConnection; *)
      client_ip = Ip.null;
      client_md4 = Md4.null;
      client_last_filereqs = 0;
(*      client_chunks = [||]; *)
      client_download = None;
(*      client_block = None; *)
(*      client_zones = []; *)
      client_file_queue = [];
      client_tags = [];
      client_name = "";
      client_all_files = None;
(*      client_all_chunks = ""; *)
      client_rating = 0;
      client_brand = Brand_unknown;
      client_mod_brand = Brand_mod_unknown;
      client_checked = false;
      client_connected = false;
      client_downloaded = Int64.zero;
      client_uploaded = Int64.zero;
      client_banned = false;
      client_score = 0;
      client_next_queue = 0;
      client_rank = 0;
      client_connect_time = 0;
      client_requests_received = 0;
      client_requests_sent = 0;
      client_indirect_address = None;      
      client_slot = SlotNotAsked; 
      client_debug = Intset.mem s.DonkeySources.source_num !debug_clients;
      client_pending_messages = [];
      client_emule_proto = emule_proto ();
      client_comp = None;
      client_connection_time = 0;
      } and
    client_impl = {
      dummy_client_impl with            
      impl_client_val = c;
      impl_client_ops = client_ops;
      impl_client_upload = None;
    }
  in
  Heap.set_tag c tag_client;
  CommonClient.new_client_with_num client_impl s.DonkeySources.source_num;
  H.add clients_by_kind c;
  clients_root := c :: !clients_root;
  c

let new_client key =
  try
    H.find clients_by_kind { dummy_client with client_kind = key }
  with _ ->
      create_client key

let create_client = ()
      
      (*
let new_client_with_num key num =
  try
    { dummy_client with client_kind = key }  
  with _ ->
      create_client key
        *)

let find_client_by_key key = 
  H.find clients_by_kind { dummy_client with client_kind = key }
  
let client_type c =
  client_type (as_client c)

let set_client_type c t=
  set_client_type (as_client c) t

let friend_add c =
  friend_add (as_client c)
      
let set_client_name c name md4 =
  if name <> c.client_name || c.client_md4 <> md4 then begin
(*      hashtbl_remove clients_by_name c.client_name c;   *)

      c.client_name <- name;
      c.client_md4 <- md4;
      
      (*
      if not (Hashtbl.mem clients_by_name c.client_name) then
        Hashtbl.add clients_by_name c.client_name c;
*)

      (*
      try      
        let kind = Indirect_location (name, md4) in
        let cc = H.find clients_by_kind { dummy_client with client_kind = kind } in
        if cc != c && client_type cc land client_friend_tag <> 0 then
          friend_add c
      with _ -> () *)
    end
    
exception ClientFound of client
let find_client_by_name name =
  try
    H.iter (fun c ->
        if c.client_name = name then raise (ClientFound c)
    ) clients_by_kind;
    raise Not_found
  with ClientFound c -> c

let udp_servers_replies = (Hashtbl.create 127 : (Md4.t, server) Hashtbl.t)
    
let file_groups = (Hashtbl.create 1023 : (Md4.t, file_group) Hashtbl.t)

let file_md4s_to_register = ref ([] : file list)
  
module UdpClientWHashtbl = Weak2.Make(struct
      type t = udp_client
      let hash c = Hashtbl.hash (c.udp_client_ip, c.udp_client_port)
      
      let equal x y = x.udp_client_port = y.udp_client_port
        && x.udp_client_ip = y.udp_client_ip
    end)

let udp_clients = UdpClientWHashtbl.create 1023

let local_mem_stats buf = 
  Gc.compact ();
  let client_counter = ref 0 in
  let unconnected_unknown_clients = ref 0 in
  let uninteresting_clients = ref 0 in
  let aliased_clients = ref 0 in
  let connected_clients = ref 0 in
  let closed_connections = ref 0 in
  let unlocated_client = ref 0 in
  let bad_numbered_clients = ref 0 in
  let disconnected_alias = ref 0 in
  let dead_clients = ref 0 in
  let buffers = ref 0 in
  let waiting_msgs = ref 0 in
  let connected_clients_by_num = Hashtbl.create 100 in
  H.iter (fun c ->
(*
      if c.client_num <> num then begin
          incr bad_numbered_clients;
          try
            let cc = Hashtbl.find clients_by_num c.client_num in
            if cc.client_sock = None then incr disconnected_alias;
          with _ -> incr dead_clients;
end;
*)
      let num = client_num c in
      incr client_counter;
      match c.client_source.DonkeySources.source_sock with
        NoConnection -> begin
            match c.client_kind with
              Indirect_address _ -> incr unconnected_unknown_clients
            | _ -> ()
          end
      | ConnectionWaiting _  -> ()
      | Connection sock ->
          let buf_len, nmsgs = TcpBufferedSocket.buf_size sock in
          (try
              Hashtbl.find connected_clients_by_num num
            with _ -> 
                incr connected_clients;
                waiting_msgs := !waiting_msgs + nmsgs;
                buffers := !buffers + buf_len;
(*
                Printf.bprintf buf "%d: %6d/%6d\n" num
                  buf_len nmsgs *)
          );
          if TcpBufferedSocket.closed sock then
            incr closed_connections;
  ) clients_by_kind;
  
  let bad_clients_in_files = ref 0 in
  Hashtbl.iter (fun _ file ->
      DonkeySources.iter_all_sources (fun s ->
          match s.DonkeySources.source_sock with
            NoConnection -> begin
                match s.DonkeySources.source_uid with
                  Indirect_address _ -> incr bad_clients_in_files
                | _ -> ()
              end
          | _ -> ()              
      ) file.file_sources;
  ) files_by_md4;
  
  Printf.bprintf buf "Clients: %d\n" !client_counter;
  Printf.bprintf buf "   Bad Clients: %d/%d\n" !unconnected_unknown_clients
    !bad_clients_in_files;
  Printf.bprintf buf "   Read Buffers: %d\n" !buffers;
  Printf.bprintf buf "   Write Messages: %d\n" !waiting_msgs;
  Printf.bprintf buf "   Uninteresting clients: %d\n" !uninteresting_clients;
  Printf.bprintf buf "   Connected clients: %d\n" !connected_clients;
  Printf.bprintf buf "   Aliased clients: %d\n" !aliased_clients;
  Printf.bprintf buf "   Closed clients: %d\n" !closed_connections;
  Printf.bprintf buf "   Unlocated clients: %d\n" !unlocated_client;
  Printf.bprintf buf "   Bad numbered clients: %d\n" !bad_numbered_clients;
  Printf.bprintf buf "   Dead clients: %d\n" !dead_clients;
  Printf.bprintf buf "   Disconnected aliases: %d\n" !disconnected_alias;
  ()
  
let remove_client c =
  client_remove (as_client c);
(*  hashtbl_remove clients_by_kind c.client_kind c; *)
(*  hashtbl_remove clients_by_name c.client_name c *)
  ()


let friend_remove c = 
  friend_remove  (as_client c)

let last_search = ref (Intmap.empty : int Intmap.t)
  
(* indexation *)
let comments = (Hashtbl.create 127 : (Md4.t,string) Hashtbl.t)

let comment_filename = Filename.concat file_basedir "comments.met"
  
let (results_by_md4 : (Md4.t, result) Hashtbl.t) = Hashtbl.create 1023
  
let history_file = Filename.concat file_basedir "history.met"
let history_file_oc = ref (None : out_channel option)

  
  
let last_connected_server () =
  match !servers_list with 
  | s :: _ -> s
  | [] -> 
      servers_list := 
      Hashtbl.fold (fun key s l ->
          s :: l
      ) servers_by_key [];
      match !servers_list with
        [] -> raise Not_found
      | s :: _ -> s

          
let all_servers () =
  Hashtbl.fold (fun key s l ->
      s :: l
  ) servers_by_key []

let string_of_file_state s =
  match  s with
  | FileDownloading -> "File Downloading"
  | FilePaused -> "File Paused"
  | FileDownloaded -> "File Downloaded"
  | FileShared     -> "File Shared"
  | FileCancelled -> "File Cancelled"
  | FileNew -> "File New"
  | FileAborted s -> Printf.sprintf "Aborted: %s" s
  | FileQueued -> "File Queued"
      
let left_bytes = "MLDK"

let overnet_server_ip = ref Ip.null
let overnet_server_port = ref 0

        
let brand_to_string b =
  match b with
    Brand_unknown -> "unknown"
  | Brand_edonkey -> "eDonkey"
  | Brand_cdonkey -> "cDonkey"
  | Brand_mldonkey1 -> "old mldonkey"
  | Brand_mldonkey2 -> "new mldonkey"
  | Brand_mldonkey3 -> "trusted mldonkey"
  | Brand_overnet -> "Overnet"
  | Brand_newemule -> "eMule"
  | Brand_lmule -> "xMule"
  | Brand_shareaza -> "shareaza"
  | Brand_server -> "server"
  | Brand_amule -> "aMule"
  | Brand_lphant -> "lPhant"

let brand_mod_to_string b =
  match b with
    Brand_mod_unknown -> "unknown"
  | Brand_mod_extasy -> "Extasy"
  | Brand_mod_hunter -> "Hunter"
  | Brand_mod_sivka -> "Sivka"
  | Brand_mod_ice -> "IcE"
  | Brand_mod_plus -> "Plus"
  | Brand_mod_lsd -> "LSD"
  | Brand_mod_maella -> "Maella"
  | Brand_mod_pille -> "Pille"
  | Brand_mod_morphkad -> "MorphKad"
  | Brand_mod_efmod -> "eF-MOD"
  | Brand_mod_xtreme -> "Xtreme"
  | Brand_mod_bionic -> "Bionic"
  | Brand_mod_pawcio -> "Pawcio"
  | Brand_mod_zzul -> "ZZUL"
  | Brand_mod_blackhand -> "Black Hand"
  | Brand_mod_lovelace -> "lovelace"
  | Brand_mod_morphnext -> "MorphNext"
  | Brand_mod_fincan -> "fincan"
  | Brand_mod_ewombat -> "eWombat"
  | Brand_mod_morph -> "Morph"
  | Brand_mod_mortillo -> "MorTillo"
  | Brand_mod_lh -> "LionHeart"
  | Brand_mod_emulespana -> "emulEspa\241a"
  | Brand_mod_blackrat -> "BlackRat"
  | Brand_mod_enkeydev -> "enkeyDev"
  | Brand_mod_gnaddelwarz -> "Gnaddelwarz"
  | Brand_mod_phoenixkad -> "pHoeniX-KAD"
  | Brand_mod_koizo -> "koizo"
  | Brand_mod_ed2kfiles -> "ed2kFiles"
  | Brand_mod_athlazan -> "Athlazan"
  | Brand_mod_cryptum -> "Cryptum"
  | Brand_mod_lamerzchoice -> "LamerzChoice"
  | Brand_mod_notdead -> "NotDead"
  | Brand_mod_peace -> "peace"
  | Brand_mod_goldicryptum -> "GoldiCryptum"
  | Brand_mod_eastshare -> "EastShare"
  | Brand_mod_mfck -> "[MFCK]"
  | Brand_mod_echanblard -> "eChanblard"
  | Brand_mod_sp4rk -> "Sp4rK"
  | Brand_mod_powermule -> "PowerMule"
  | Brand_mod_bloodymad -> "bloodymad"
  | Brand_mod_roman2k -> "Roman2K"
  | Brand_mod_gammaoh -> "GaMMaOH"
  | Brand_mod_elfenwombat -> "ElfenWombat"
  | Brand_mod_o2 -> "O2"
  | Brand_mod_dm -> "DM"
  | Brand_mod_sfiom -> "SF-IOM"
  | Brand_mod_magic_elseve -> "Magic-Elseve"
  | Brand_mod_schlumpmule -> "SchlumpMule"
  | Brand_mod_lc -> "LC"
  | Brand_mod_noamson -> "NoamSon"
  | Brand_mod_stormit -> "Stormit"
  | Brand_mod_omax -> "OMaX"
  | Brand_mod_mison -> "Mison"
  | Brand_mod_phoenix -> "Phoenix"
  | Brand_mod_spiders -> "Spiders"
  | Brand_mod_iberica -> "Ib\233rica"
  | Brand_mod_mortimer -> "Mortimer"
  | Brand_mod_stonehenge -> "Stonehenge"
  | Brand_mod_xlillo -> "Xlillo"
  | Brand_mod_imperator -> "ImperatoR"
  | Brand_mod_raziboom -> "Raziboom"
  | Brand_mod_khaos -> "Khaos"
  | Brand_mod_hardmule -> "Hardmule"
  | Brand_mod_sc -> "SC"
  | Brand_mod_cy4n1d -> "Cy4n1d"
  | Brand_mod_dmx -> "DMX"
  | Brand_mod_ketamine -> "Ketamine"
  | Brand_mod_blackmule -> "Blackmule"
  | Brand_mod_morphxt -> "MorphXT"
  | Brand_mod_ngdonkey -> "ngdonkey"
  | Brand_mod_cyrex -> "Cyrex"
      
(*************************************************************

The following structures are used to locally index search
  results, to be able to search in history.
  
**************************************************************)  
  
let (store: CommonTypes.result_info Store.t) = 
  Store.create (Filename.concat file_basedir "store")
  
module Document = struct
    type t = Store.index
      
    let num t = Store.index t
    let filtered t = Store.get_attrib store t
    let filter t bool = Store.set_attrib store t bool
  end

let doc_value doc = Store.get store doc
  
module DocIndexer = Indexer2.FullMake(Document)

open Document
  
let index = DocIndexer.create ()

let check_result r tags =
  if r.result_names = [] || r.result_size = Int64.zero then begin
      if !verbose then begin
          lprintf "BAD RESULT:\n";
          List.iter (fun tag ->
              lprintf "[%s] = [%s]" tag.tag_name
                (match tag.tag_value with
                  String s -> s
                | Uint64 i | Fint64 i -> Int64.to_string i
                | Addr _ -> "addr");
              lprintf "\n";
          ) tags;
        end;
      false
    end
  else true
    

let result_of_file md4 tags =
  
  let rec r = { 
      result_num = 0;
      result_network = network.network_num;
      result_md4 = md4;
      result_names = [];
      result_size = Int64.zero;
      result_tags = [];
      result_type = "";
      result_format = "";
      result_comment = "";
      result_done = false;
    } in
  List.iter (fun tag ->
      match tag with
        { tag_name = "filename"; tag_value = String s } ->
          r.result_names <- s :: r.result_names
      | { tag_name = "size"; tag_value = Uint64 v } ->
          r.result_size <- v;
      | { tag_name = "format"; tag_value = String s } ->
          r.result_tags <- tag :: r.result_tags;
          r.result_format <- s
      | { tag_name = "type"; tag_value = String s } ->
          r.result_tags <- tag :: r.result_tags;
          r.result_type <- s
      | _ ->
          r.result_tags <- tag :: r.result_tags
  ) tags;
  if check_result r tags then Some r else None

      
(*************************************************************

Define a function to be called when the "mem_stats" command
  is used to display information on structure footprint.
  
**************************************************************)  

let _ =
  Heap.add_memstat "DonkeyGlobals" (fun _ ->
(* current_files *)
      lprintf "Current files: %d\n" (List.length !current_files);
(* clients_by_name *)
(*      let list = Hashtbl2.to_list clients_by_name in
      lprintf "Clients_by_name: %d\n" (List.length list);
      List.iter (fun c ->
          lprintf "[%d %s]" (client_num c)
          (if Hashtbl.mem clients_by_kind c.client_kind then "K" else " ") ;
     ) list;
     lprintf "\n";
*)
      
(* clients_by_kind *)
      let list = H.to_list clients_by_kind in
      lprintf "Clients_by_kind: %d\n" (List.length list);
      List.iter (fun c ->
          lprintf "[%d ok: %s rating: %d]\n" 
          (client_num c)
          (string_of_date (c.client_source.DonkeySources.source_age))
(* TODO: add connection state *)
          c.client_rating
          ;
     ) list;
      lprintf "\n";
  );
      
  Heap.add_memstat "DonkeyGlobals" local_mem_stats

    
(*************************************************************

   Save the state of the client positive queries for files
 if a JoinQueue message was sent. Use this information if
 an AvailableSlot message is received while not JoinQueue
 message was sent (client_asked_for_slot false).
  
**************************************************************)
  
  
let join_queue_by_md4 = Hashtbl.create 13
let join_queue_by_id  = Hashtbl.create 13

let client_id c = 
  match c.client_kind with
    Direct_address (ip, port) -> (ip, port, zero)
  | Indirect_address (ip, port, id) -> (ip, port, id)
  | Invalid_address _ -> (Ip.null, 0, zero)
      
let save_join_queue c =
  if c.client_file_queue <> [] then
    let files = List.map (fun (file, chunks, _) ->
          file, Array.copy chunks
      ) c.client_file_queue in
    begin
      if c.client_debug then 
        lprintf "Saving %d files associated with %s\n"
        (List.length files) (Md4.to_string c.client_md4);
      Hashtbl.add join_queue_by_md4 c.client_md4 (files, last_time ());
      try
        let id = client_id c in
        Hashtbl.add join_queue_by_id id (files, last_time ());
      with _ -> ()
    end

let half_hour = 30 * 60
let clean_join_queue_tables () =
  let current_time = last_time () in
  
  let list = Hashtbl2.to_list2 join_queue_by_md4 in
  Hashtbl.clear join_queue_by_md4;
  List.iter (fun (key, ((v,time) as e)) ->
      if time + half_hour > current_time then
        Hashtbl.add join_queue_by_md4 key e
  ) list;
    
  let list = Hashtbl2.to_list2 join_queue_by_id in
  Hashtbl.clear join_queue_by_id;
  List.iter (fun (key, ((v,time) as e)) ->
      if time + half_hour > current_time then
        Hashtbl.add join_queue_by_id key e
  ) list
  
  
let server_accept_multiple_getsources s =
  (s.server_flags land DonkeyProtoUdp.PingServerReplyUdp.multiple_getsources) <> 0

let server_send_multiple_replies s =
  (s.server_flags land DonkeyProtoUdp.PingServerReplyUdp.multiple_replies) <> 0
