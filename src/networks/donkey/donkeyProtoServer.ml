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

open AnyEndian
open Printf2
open Md4
open Autoconf
open LittleEndian
open CommonTypes
open CommonGlobals
  
open DonkeyTypes
open DonkeyMftp

  
let field_of_tagname s =
  match s with
  | "size" -> Field_Size
  | "filename" -> Field_Filename
  | "Artist" -> Field_Artist
  | "Album" -> Field_Album
  | "Title" -> Field_Title
  | "format" -> Field_Format
  | "type" -> Field_Type
  | s -> Field_unknown s
      
  
let tagname_of_field field =
  match field with
    Field_Size -> "size"
  | Field_Filename -> "filename"
  | Field_Artist -> "Artist"
  | Field_Album -> "Album"
  | Field_Title -> "Title"
  | Field_Format -> "format"
  | Field_Type -> "type"
  | Field_unknown s -> s

  
module Connect = struct 
    type t = {
        md4 : Md4.t;
        ip: Ip.t;
        port: int;
        tags :  tag list;
      }
    
    let names_of_tag =
      [
       "\001", "name";
       "\017", "version";
       "\015", "port";
       "\032", "extended";
      ]
    
    let parse len s =
      let md4 = get_md4 s 1 in
      let ip = get_ip s 17 in
      let port = get_port s 21 in
(*      lprintf "port: %d\n" port;*)
      let tags, pos = get_tags s 23 names_of_tag in
      {
        md4 = md4;
        ip = ip;
        port = port;
        tags = tags;
      }
    
    let print t = 
      lprintf "CONNECT:\n";
      lprintf "MD4: %s\n" (Md4.to_string t.md4); 
      lprintf "ip: %s\n" (Ip.to_string t.ip);
      lprintf "port: %d\n" t.port;
      lprintf "tags: ";
      print_tags t.tags
    
    let bprint oc t = 
      Printf.bprintf oc "CONNECT:\n";
      Printf.bprintf oc "%s\n" (Md4.to_string t.md4); 
      Printf.bprintf oc "%s\n" (Ip.to_string t.ip);
      Printf.bprintf oc "%d\n" t.port;
      Printf.bprintf oc "TAGS:\n";
      bprint_tags oc t.tags;
       Printf.bprintf oc "\n"

    let write buf t =
      buf_md4 buf t.md4;
      buf_ip buf t.ip;
      buf_port buf t.port;
      buf_tags buf t.tags names_of_tag  
  end

module ChatRooms = struct (* request: 57 *)
    
    (* example:
ascii [ 9(3)(4)(0) M a i n(0)(0)(2)(0)(5)(0) M u s i c(0)(0)(3)(0)(3)(0) A r t(0)(0)(4)(0)] 
*)
    
    
    type channel = {
        name : string;
        number : int;
      }
    
    type t = channel list
      
    let parse len s =
      let nchans = get_uint8 s 1 in
      let rec iter s pos nchans =
        if nchans = 0 then [] else
        let name, pos = get_string s pos in
        let number = get_int s pos in
        { name = name; number = number; } :: (iter s (pos+4) (nchans-1))
      in
      iter s 2 nchans

    let print t =
      lprintf "CHANNELS:\n";
      List.iter (fun c ->
          lprintf "  %s: %d\n" c.name c.number;
      ) t

     let bprint oc t =
      Printf.bprintf oc "CHANNELS:\n";
      List.iter (fun c ->
          Printf.bprintf oc "  %s: %d\n" c.name c.number;
      ) t

    let write buf t =
      buf_int buf (List.length t);
      List.iter (fun c ->
          buf_string buf c.name;
          buf_int buf c.number) t
      
  end

module SetID = struct 
    type t = bool * Ip.t
      
    
    let parse len s = 
      len = 9, get_ip s 1
    
    let print (zlib, t) = 
      lprintf "SET_ID: %s\n" (if zlib then "Zlib" else "");
      lprintf "id: %s\n" (Ip.to_string t)

    let bprint oc (zlib, t) = 
      Printf.bprintf oc "SET_ID: %s\n"  (if zlib then "Zlib" else "");
      Printf.bprintf oc "id: %s\n" (Ip.to_string t)
    
    let write buf (zlib, t) =
      if zlib then buf_int buf 1;
      buf_ip buf t
  
  end

let unit = ()

module AckID = struct 
    type t = unit
    
    let parse len s = ()
    
    let print t = 
      lprintf "ACK_ID:\n"

    let bprint oc t = 
      Printf.bprintf oc "ACK_ID\n"
    
    let write (buf: Buffer.t) (t: t) = unit

    let t = (() : t)
  end

module Message = struct 
    type t = string
    
    let parse len s = 
      let v, pos = get_string s 1 in
      v
    
    let print t = 
      lprintf "MESSAGE:\n";
      lprintf "message = \"%s\"" (String.escaped t)
    
    let bprint oc t = 
      Printf.bprintf oc "MESSAGE:\n";
      Printf.bprintf oc "%s\n" (String.escaped t)

    let write buf t =
      buf_string buf t
  end

module Share = struct 
    
    type t = tagged_file list
    
    let names_of_tag =
      [
        "\001", "filename";
        "\002", "size";
        "\003", "type";
        "\004", "format";
      ]
    
    let rec get_files  s pos n =
      if n = 0 then [], pos else
      let md4 = get_md4 s pos in
      let ip = get_ip s (pos + 16) in
      let port = get_port s (pos + 20) in
      let tags, pos = get_tags s (pos+22) names_of_tag in
      let file = {
          f_md4 = md4;
          f_ip = ip;
          f_port = port;
          f_tags = tags;
        } in
      let files, pos =  get_files s pos (n-1) in
      file :: files, pos
    
    
    let parse len s =
      let n = get_int s 1 in
      let files, pos = get_files s 5 n in
      files
    
    let print t = 
      lprintf "SHARED:\n";
      List.iter (fun t ->
          lprintf "FILE:\n";
          lprintf "  MD4: %s\n" (Md4.to_string t.f_md4);
          lprintf "  ip: %s\n" (Ip.to_string t.f_ip);
          lprintf "  port: %d\n" t.f_port;
          lprintf "  tags: ";
          print_tags t.f_tags;
          lprint_newline ();) t
    
    let bprint oc t = 
      Printf.bprintf oc "SHARED:\n";
      List.iter (fun t ->
          Printf.bprintf oc "FILE:\n";
          Printf.bprintf oc " %s\n" (Md4.to_string t.f_md4);
          Printf.bprintf oc "%s\n" (Ip.to_string t.f_ip);
          Printf.bprintf oc "%d\n" t.f_port;
          Printf.bprintf oc "TAGS:\n";
          bprint_tags oc t.f_tags;
          Printf.bprintf oc "\n"
      ) t
    
    let rec write_files buf files =
      match files with
        [] -> ()
      | file :: files ->
          buf_md4 buf file.f_md4;
          buf_ip buf file.f_ip;
          buf_port buf file.f_port;
          buf_tags buf file.f_tags names_of_tag;
          write_files buf files
    
    let write buf t = 
      buf_int buf (List.length t);
      write_files buf t
    
    let rec write_files_max buf files nfiles max_len =
      let prev_len = Buffer.length buf in
      match files with
        [] -> nfiles, prev_len
      | file :: files ->
          buf_md4 buf file.f_md4;
          buf_ip buf file.f_ip;
          buf_port buf file.f_port;
          buf_tags buf file.f_tags names_of_tag;
          if Buffer.length buf < max_len then
            write_files_max buf files (nfiles+1) max_len
          else
            nfiles, prev_len
      
  end

module Info = struct 
    type t = int * int
    
    let parse len s =
      
      if len <> 9 then begin
          lprintf "SERVER INFO WITH LENGTH %d !!!!!!\n" len;
        end;
      let users = get_int s 1 in
      let files = get_int s 5 in
      users, files
    
    let print (users, files) = 
      lprintf "INFO:\n";
      lprintf "users: %d files: %d\n"  users files

   let bprint oc (users, files) = 
      Printf.bprintf oc "INFO:\n";
      Printf.bprintf oc "%d\n %d\n"  users files
    
    let write buf (users, files) =
      buf_int buf users;
      buf_int buf files
  end

module ServerList = struct 
    type server = {
        ip : Ip.t;
        port : int;
      }
    
    type t = server list
      
    let parse len s = 
      let n = get_uint8 s 1 in
      let rec iter i  =
        if i = n then [] else
        let ip = get_ip s (2 + i * 6) in
        let port = get_port s (6+ i * 6) in
        { ip = ip; port = port; } :: (iter (i+1))
      in
      iter 0
          
    let print t = 
      lprintf "SERVER LIST\n";
      List.iter (fun l -> 
          lprintf "   %s : %d\n" (Ip.to_string l.ip) l.port;
      ) t

    let bprint oc t = 
      Printf.bprintf oc "SERVER LIST\n";
      List.iter (fun l -> 
          Printf.bprintf oc "%s:%d\n" (Ip.to_string l.ip) l.port;
      ) t
      
    let write buf t = 
      buf_int8 buf (List.length t);
      List.iter (fun l ->
          buf_ip buf l.ip;
          buf_int16 buf l.port
      ) t
  end

  

module ServerInfo = struct 
    type t = {
        md4 : Md4.t;
        ip: Ip.t;
        port: int;
        tags :  tag list;
      }
    
    let names_of_tag =
      [
        "\001", "name";
        "\011", "description";
      ]
    
    let parse len s =
      let md4 = get_md4 s 1 in
      let ip = get_ip s 17 in
      let port = get_port s 21 in
(*      lprintf "port: %d\n" port; *)
      let tags, pos = get_tags s 23 names_of_tag in
      {
        md4 = md4;
        ip = ip;
        port = port;
        tags = tags;
      }
    
    let print t = 
      lprintf "SERVER INFO:\n";
      lprintf "MD4: %s\n" (Md4.to_string t.md4);
      lprintf "ip: %s\n" (Ip.to_string t.ip);
      lprintf "port: %d\n" t.port;
      lprintf "tags: ";
      print_tags t.tags

    let bprint oc t = 
      Printf.bprintf oc "SERVER INFO:\n";
      Printf.bprintf oc "%s\n" (Md4.to_string t.md4);
      Printf.bprintf oc "%s\n" (Ip.to_string t.ip);
      Printf.bprintf oc "%d\n" t.port;
      Printf.bprintf oc "TAGS:\n";
      bprint_tags oc t.tags;
      Printf.bprintf oc "\n"
    
    let write buf t =
      buf_md4 buf t.md4;
      buf_ip buf t.ip;
      buf_port buf t.port;
      buf_tags buf t.tags names_of_tag
  
  end

module QueryReply  = struct 
      
    type t = tagged_file list

    let names_of_tag = [
        "\001", "filename";
        "\002", "size";
        "\003", "type";
        "\004", "format";
        "\021", "availability";
	"\048", "completesources";
      ]        

          
    let rec get_files  s pos n =
      if n = 0 then [], pos else
        try
      let md4 = get_md4 s pos in
      let ip = get_ip s (pos + 16) in
      let port = get_port s (pos + 20) in
      let tags, pos = get_tags s (pos+22) names_of_tag in
      let file = {
          f_md4 = md4;
          f_ip = ip;
          f_port = port;
          f_tags = tags;
        } in
      let files, pos =  get_files s pos (n-1) in
      file :: files, pos
        with _ -> 
          raise Not_found

    let get_replies s pos = 
      let n = get_int s pos in
      let files, pos = get_files s (pos+4) n in
      files
    
    let parse len s = get_replies s 1
    
    let print t = 
      lprintf "FOUND:\n";
      List.iter (fun t ->
          lprintf "FILE:\n";
          lprintf "  MD4: %s\n" (Md4.to_string t.f_md4);
          lprintf "  ip: %s\n" (Ip.to_string t.f_ip);
          lprintf "  port: %d\n" t.f_port;
          lprintf "  tags: ";
          print_tags t.f_tags;
          lprint_newline ();) t

    let bprint oc t = 
      Printf.bprintf oc "FOUND:\n";
      List.iter (fun t ->
          Printf.bprintf oc "FILE:\n";
          Printf.bprintf oc "%s\n" (Md4.to_string t.f_md4);
          Printf.bprintf oc "%s\n" (Ip.to_string t.f_ip);
          Printf.bprintf oc "%d\n" t.f_port;
          Printf.bprintf oc "TAGS:\n";
          bprint_tags oc t.f_tags;
             Printf.bprintf oc "\n"
          ) t
    
    let rec write_files buf files =
      match files with
        [] -> ()
      | file :: files ->
          buf_md4 buf file.f_md4;
          buf_ip buf file.f_ip;
          buf_port buf file.f_port;
          buf_tags buf file.f_tags names_of_tag;
          write_files buf files

    let write_replies buf t =          
      buf_int buf (List.length t);
      write_files buf t
      
      let write buf t = 
        write_replies buf t;
      buf_int8 buf 0

  end

let unit = ()
module NoArg = functor(M: sig val m : string end) -> (struct 
        type t = unit
        
        let parse len s = ()
        
        let print t = 
          lprintf "%s:\n" M.m
        
        let write (buf: Buffer.t) (t: t) = unit
          
        let t = (() : t)
      end : sig
        type t
          val parse : int -> string  -> t
          val print : t -> unit
          val write : Buffer.t -> t  -> unit
          val t :t 
          end
      )

module QueryNext = NoArg(struct let m = "QUERY NEXT" end)

  
  
module Query  = struct (* request 22 *)
    
    let names_of_tag =
      [
        "\002", "size";
        "\003", "type";
        "\004", "format";
        "\021", "availability";
	"\048", "completesources";
      ]
    
    let rec parse_query s pos =
      let t = get_uint8 s pos in
      match t with
        0 -> 
          let t = get_uint8 s (pos+1) in
          begin
            match t with
              0 -> 
                let q1, pos  = parse_query s (pos + 2) in
                let q2, pos  = parse_query s pos in
                QAnd (q1,q2), pos
            | 1 -> 
                let q1, pos  = parse_query s (pos + 2) in
                let q2, pos  = parse_query s pos in
                QOr (q1,q2), pos
            | 2 -> 
                let q1, pos  = parse_query s (pos + 2) in
                let q2, pos  = parse_query s pos in
                QAndNot (q1,q2), pos
            |_ -> failwith "Unknown QUERY operator"
          end
      | 1 -> let s, pos = get_string s (pos + 1) in QHasWord s, pos
      | 2 -> 
          let field, pos = get_string s (pos + 1) in
          let name, pos = get_string s pos in          
          let name = try
              List.assoc name names_of_tag
            with _ -> name
          in
          
          QHasField (field_of_tagname name, field), pos
      
      | 3 -> 
          let field = get_uint64_32 s (pos + 1) in
          let minmax = get_uint8 s (pos + 5) in
          let name, pos = get_string s (pos + 6) in
          let name = try
              List.assoc name names_of_tag
            with _ -> name
          in
          begin
            match minmax with
              1 -> QHasMinVal (field_of_tagname name, field)
            | 2 -> QHasMaxVal (field_of_tagname name, field)
            | _ -> failwith "Unknown QUERY minmax"
          end, pos
      | 4 -> QHasWord "", pos + 1
      | _ -> failwith "Unknown QUERY format"
    
    let parse len s = 
      let t, pos = parse_query s 1 in t

(*
  type = "Col" pour voir les collections
    Fields:
  "Album" | "Artist" | "Title"
    
    *)
    
    let rec print_query t =
      match t with
        QOr (q1, q2) -> 
          print_query q1; 
          lprint_string " OR ";
          print_query q2
      | QAnd (q1, q2) -> 
          print_query q1; 
          lprint_string " AND ";
          print_query q2
      | QAndNot (q1, q2) -> 
          print_query q1; 
          lprint_string " NOT ";
          print_query q2
      
      | QHasWord s ->
          lprintf "Contains[%s]" s
      | QHasField (name, field) ->
          lprintf "Field[%s] = [%s]" (string_of_field name) field
      | QHasMinVal (name, field) ->
          lprintf "Field[%s] > [%s]" (string_of_field name) (Int64.to_string field)
      | QHasMaxVal (name, field) ->
          lprintf "Field[%s] < [%s]" (string_of_field name) (Int64.to_string field)
      |	QNone ->
          lprintf "print_query: QNone in query\n";
          ()
    
    let  print t = 
      lprintf "QUERY";
      print_query t
    
    
    let rec bprint_query oc t =
      match t with
        QOr (q1, q2) -> 
          print_query q1; 
          Printf.bprintf oc " OR ";
          print_query q2
      | QAnd (q1, q2) -> 
          print_query q1; 
          Printf.bprintf oc " AND ";
          print_query q2
      | QAndNot (q1, q2) -> 
          print_query q1; 
          Printf.bprintf oc " NOT ";
          print_query q2
      
      | QHasWord s ->
          Printf.bprintf oc "Contains[%s]" s
      | QHasField (name, field) ->
          Printf.bprintf oc "Field[%s] = [%s]" (string_of_field name) field
      | QHasMinVal (name, field) ->
          Printf.bprintf oc "Field[%s] > [%s]" (string_of_field name) (Int64.to_string field)
      | QHasMaxVal (name, field) ->
          Printf.bprintf oc "Field[%s] < [%s]" (string_of_field name) (Int64.to_string field)
      |	QNone ->
          lprintf "print_query: QNone in query\n";
          ()
    
    
    let bprint oc t = 
      Printf.bprintf oc "QUERY:\n";
      bprint_query oc t;
      Printf.bprintf oc "\n"
    
    let rec write buf t = 
      match t with
        QOr (q1, q2) -> 
          buf_int8 buf 0;
          buf_int8 buf 1;
          write buf  q1; 
          write buf  q2; 
      | QAnd (q1, q2) -> 
          buf_int8 buf 0;
          buf_int8 buf 0;
          write buf  q1; 
          write buf  q2; 
      | QAndNot (q1, q2) -> 
          buf_int8 buf 0;
          buf_int8 buf 2;
          write buf  q1; 
          write buf  q2; 
      | QHasWord s ->
          buf_int8 buf 1;
          buf_string buf s
      | QHasField (name, field) ->
          
          let name = tagname_of_field name in
          let name = try
                rev_assoc name names_of_tag
            with _ -> name in
          
          buf_int8 buf 2;
          buf_string buf field;
          buf_string buf name
      
      | QHasMinVal (name, field) ->
          
          let name = tagname_of_field name in
          let name = try 
              rev_assoc name names_of_tag
            with _ -> name
          in
          
          buf_int8 buf 3;
          buf_int64_32 buf field;
          buf_int8 buf 1;
          buf_string buf name

      | QHasMaxVal (name, field) ->
          
          let name = tagname_of_field name in
          let name = try
              rev_assoc name names_of_tag
              with _ -> name in

          buf_int8 buf 3;
          buf_int64_32 buf field;
          buf_int8 buf 2;
          buf_string buf name

      |	QNone ->
	  lprintf "print_query: QNone in query\n";
	  ()
            
  end

  
module QueryUsers = struct (* request 26 *)
    (* TODO: Utilise le meme format que Query *)
    
    type t = string
      
    let parse len s =
      let targ = get_uint8 s 1 in
      match targ with
        4 -> ""
      | 1 -> 
          let name, pos = get_string s 2 in
          name
      | _ -> 
          lprintf "QueryUsers: unknown tag %d\n" targ;
          raise Not_found
          
    let print t =
      lprintf "QUERY USERS [%s]\n" t

     let bprint oc t =
      Printf.bprintf oc "QUERY USERS [%s]\n" t
      
    let write buf t =
      if t = "" then
        buf_int8 buf 4
      else begin
          buf_int8 buf 1;
          buf_string buf t
        end
  end
  
module QueryUsersReply = struct (* request 67 *)
    type client = {
        md4 : Md4.t;
        ip: Ip.t;
        port: int;
        tags : tag list;
      }
    
    type t = client list
    
    let names_of_tag =
      [
        "\001", "name";
        "\017", "version";
        "\015", "port";
      ]
    
    let rec parse_clients s pos nclients left =
      if nclients = 0 then List.rev left else
      let md4 = get_md4 s pos in
       let ip = get_ip s (pos+16) in
      let port = get_port s (pos+20) in
      let tags, pos = get_tags s (pos+22) names_of_tag in
      parse_clients s pos (nclients-1) (
        {
          md4 = md4;
          ip = ip;
          port = port;
          tags = tags;
        } :: left)
    
    let parse len s =
      let nclients = get_int s 1 in
      parse_clients s 5 nclients []
    
    let print t = 
      lprintf "QUERY USERS REPLY:\n";
      List.iter (fun t ->
          lprintf "MD4: %s\n" (Md4.to_string t.md4); 
          lprintf "ip: %s\n" (Ip.to_string t.ip);
          lprintf "port: %d\n" t.port;
          lprintf "tags: ";
          print_tags t.tags; lprint_newline ();) t

    let bprint oc t = 
      Printf.bprintf oc "QUERY USERS REPLY:\n";
      List.iter (fun t ->
          Printf.bprintf oc "%s\n" (Md4.to_string t.md4); 
          Printf.bprintf oc "%s\n" (Ip.to_string t.ip);
          Printf.bprintf oc "%d\n" t.port;
          Printf.bprintf oc "TAGS:\n";
          bprint_tags oc  t.tags;
	  Printf.bprintf oc "\n"
          ) t
    
    let write buf t =
      buf_int buf (List.length t);
      List.iter (fun t ->
          buf_md4 buf t.md4;
          buf_ip buf t.ip;
          buf_port buf t.port;
          buf_tags buf t.tags names_of_tag) t
  end
  
module QueryLocation  = struct 
    type t = Md4.t
      
    let parse len s = 
      get_md4 s 1
      
    let print t = 
      lprintf "QUERY LOCATION OF %s" (Md4.to_string t)

    let bprint oc t = 
      Printf.bprintf oc "QUERY LOCATION OF %s\n" (Md4.to_string t)
      
    let write buf t = 
      buf_md4 buf t
  end

module QueryLocationReply  = struct 
    type location = {
        ip : Ip.t;
        port : int;
      }
    
    type t = {
        md4: Md4.t;
        locs :location list; 
      }
    
    let parse len s = 
      let md4 = get_md4 s 1 in
      let n = get_uint8 s 17 in
      let rec iter i  =
        if i = n then [] else
        let ip = get_ip s (18 + i * 6) in
        let port = get_port s (22+ i * 6) in
        { ip = ip; port = port; } :: (iter (i+1))
      in
      let locs = iter 0 in
      { locs =locs; md4 = md4 }
    
    let print t = 
      lprintf "LOCATION OF %s\n" (Md4.to_string t.md4);
      List.iter (fun l -> 
          lprintf "   %s : %d %s\n" (Ip.to_string l.ip) l.port
            (if not (Ip.valid l.ip) then
              Printf.sprintf "(Firewalled %Ld)" (id_of_ip l.ip)
            else "");
      
      ) t.locs
    
    let bprint oc t = 
      Printf.bprintf oc "LOCATION OF %s\n" (Md4.to_string t.md4);
      List.iter (fun l -> 
          Printf.bprintf oc "%s:%d %s\n" (Ip.to_string l.ip) l.port
            (if not (Ip.valid l.ip) then
              Printf.sprintf "(Firewalled %Ld)" (id_of_ip l.ip)
            else "");
          ;
      ) t.locs
      
    let write buf t = 
      buf_md4 buf t.md4;
      buf_int8 buf (List.length t.locs);
      List.iter (fun l ->
          buf_ip buf l.ip;
          buf_port buf l.port
      ) t.locs
      
  end
  
module QueryID  = struct 
    type t = int64
      
    let parse len s = 
      id_of_ip (get_ip s 1)
      
    let print t = 
      lprintf "QUERY IP OF %Ld" t

    let bprint oc t = 
      Printf.bprintf oc "QUERY IP OF %Ld\n" t
      
    let write buf t = 
      buf_ip buf (ip_of_id t)
  end
  
module QueryIDFailed  = struct 
    type t = int64
      
    let parse len s = 
      id_of_ip (get_ip s 1)
      
    let print t = 
      lprintf "QUERY IP OF %Ld FAILED" t

    let bprint oc t = 
      Printf.bprintf oc "QUERY IP OF %Ld FAILED\n" t
      
    let write buf t = 
      buf_ip buf (ip_of_id t)
  end

module QueryIDReply  = struct 
    type t = {
        ip : Ip.t;
        port : int;
      }
          
    let parse len s = 
      let ip = get_ip s 1 in
      let port = get_port s 5 in
      { ip = ip; port = port; }
      
    let print t = 
      lprintf "IDENTIFICATION %s : %d\n" (Ip.to_string t.ip) t.port

    let bprint oc t = 
      Printf.bprintf oc "IDENTIFICATION %s : %d\n" (Ip.to_string t.ip) t.port
    
      
    let write buf t = 
      buf_ip buf t.ip;
      buf_port buf t.port
      
  end

module QueryServers  = struct 
    type t = {
        ip : Ip.t;
        port : int;
      }
      
    let parse len s = 
      let ip = get_ip s 1 in
      let port = get_port s 5 in
      { ip = ip; port = port; }
      
    let print t = 
      lprintf "QUERY SERVERS %s : %d\n" (Ip.to_string t.ip) t.port

    let bprint oc t = 
      Printf.bprintf oc "QUERY SERVERS %s : %d\n" (Ip.to_string t.ip) t.port
    
      
    let write buf t = 
      buf_ip buf t.ip;
      buf_port buf t.port
      
  end

module QueryServersReply  = struct 
    type server = {
        ip : Ip.t;
        port : int;
      }

    type t = {
        server_ip : Ip.t;
        server_port : int;
        servers: server list;
      }
      
    let rec parse_servers nservers s pos = 
      if nservers = 0 then [] else
      let ip = get_ip s pos in
      let port = get_port s (pos+4) in
      { ip = ip; port = port; } ::
      (parse_servers (nservers-1) s (pos+6))
      
    let parse len s =
      try
	let ip = get_ip s 1 in
	let port = get_port s 5 in
	let nservers = get_uint8 s 7 in
	let servers = parse_servers nservers s 8 in
	  { server_ip = ip; server_port = port; servers = servers }
      with _ ->
	let nservers = get_uint8 s 1 in
	let servers = parse_servers nservers s 2 in
	  { server_ip = Ip.null; server_port = 0; servers = servers }  
      
    let print t = 
      lprintf "SERVERS QUERY REPLY %s : %d\n" (
        Ip.to_string t.server_ip) t.server_port;
      List.iter (fun s -> 
          lprintf "   %s:%d\n" (Ip.to_string s.ip) s.port; 
      ) t.servers

     let bprint oc t = 
      Printf.bprintf oc "SERVERS QUERY REPLY:\n"; 
      Printf.bprintf oc  "%s:%d\n" (
        Ip.to_string t.server_ip) t.server_port;
      List.iter (fun s -> 
          Printf.bprintf oc  "%s:%d\n" (Ip.to_string s.ip) s.port; 
      ) t.servers
      
    let write buf t = 
      if (t.server_port = 0) then
	begin
	  buf_int8 buf (List.length t.servers);
	  List.iter (fun s -> 
		       buf_ip buf s.ip; buf_int16 buf s.port) t.servers 
	end
      else
	begin
	  buf_ip buf t.server_ip;
	  buf_port buf t.server_port;
	  buf_int8 buf (List.length t.servers);
	  List.iter (fun s -> 
		       buf_ip buf s.ip; buf_int16 buf s.port) t.servers
	end
      
  end


module Req  = struct 
    type t 
      
    let parse len s = raise Not_found
    let print t = raise Not_found
    let write buf s = raise Not_found
  end

type t = 
| ConnectReq of Connect.t
| SetIDReq of SetID.t
| AckIDReq of AckID.t
| BadProtocolVersionReq
| MessageReq of Message.t
| ShareReq of Share.t
| InfoReq of Info.t
| ServerListReq of ServerList.t
| ServerInfoReq of ServerInfo.t
| QueryReplyReq of QueryReply.t
| QueryReq of CommonTypes.query
| QueryLocationReq of QueryLocation.t
| QueryLocationReplyReq of QueryLocationReply.t
| QueryIDReq of QueryID.t
| QueryIDFailedReq of QueryIDFailed.t
| QueryIDReplyReq of QueryIDReply.t
| ChatRoomsReq of ChatRooms.t
| QueryUsersReq of QueryUsers.t
| QueryUsersReplyReq of QueryUsersReply.t
| QueryMoreResultsReq

| UnknownReq of string

(****************
                     MLdonkey extensions messages 
***************)
  
(* server to client: client has been recognized as
a mldonkey client by a mldonkey server *)
| Mldonkey_MldonkeyUserReplyReq
(* client to server: the client want to subscribe to this query *)
| Mldonkey_SubscribeReq of int * int * CommonTypes.query
(* server to client: the server send a notification to a subscription *)
| Mldonkey_NotificationReq of int * QueryReply.t
(* client to server: the client want to cancel a subscription *)
| Mldonkey_CloseSubscribeReq of int
  
let mldonkey_extensions len s =
  check_string s 1;
  let opcode = int_of_char s.[1] in
  match opcode with  
  | 1 -> 
      Mldonkey_MldonkeyUserReplyReq
  | 2 -> 
      let num = get_int s 2 in
      let lifetime = get_int s 6 in
      let query, pos = Query.parse_query s 10 in
        Mldonkey_SubscribeReq (num, lifetime, query)
  | 3 ->
      let num = get_int s 2 in
      let files = QueryReply.get_replies s 6 in
        Mldonkey_NotificationReq (num, files)
      
  | 4 ->
      let num = get_int s 2 in
      Mldonkey_CloseSubscribeReq num
  | _ -> raise Not_found
  
let rec parse magic s =
  try 
    let len = String.length s in
    if len = 0 then raise Not_found;
    let opcode = int_of_char (s.[0]) in
    match magic with 
      227 -> begin
(*    lprintf "opcode: %d\n" opcode; *)
          match opcode with 
          | 1 -> ConnectReq (Connect.parse len s)
          | 5 -> BadProtocolVersionReq 
          | 20 -> AckIDReq (AckID.parse len s)
          | 21 -> ShareReq (Share.parse len s)
          | 22 -> QueryReq (Query.parse len s)
          | 25 -> QueryLocationReq (QueryLocation.parse len s)
          | 26 -> QueryUsersReq (QueryUsers.parse len s)
          | 28 -> QueryIDReq (QueryID.parse len s)
(*    | 29 -> QueryChats (C->S) *)
(*    | 30 -> ChatMessage (C->S) *)
(*    | 31 -> JoinRoom (C->S) *)
          | 33 -> QueryMoreResultsReq
          | 50 -> ServerListReq (ServerList.parse len s)
          | 51 -> QueryReplyReq (QueryReply.parse len s)
          | 52 -> InfoReq (Info.parse len s)
          | 53 -> QueryIDReplyReq (QueryIDReply.parse len s)
          | 54 -> QueryIDFailedReq (QueryIDFailed.parse len s)
          | 56 -> MessageReq (Message.parse len s)
          | 57 -> ChatRoomsReq (ChatRooms.parse len s)
(*    | 58 -> ChatBroadcastMessage (S->C) *)
(*    | 59 -> ChatUserJoin (S->C) *)
(*    | 60 -> ChatUserLeave (S->C) *)
(*    | 61 -> ChatUsers (S->C) *)
          | 64 -> SetIDReq (SetID.parse len s)
          | 65 -> ServerInfoReq (ServerInfo.parse len s)
          | 66 -> QueryLocationReplyReq (QueryLocationReply.parse len s)
          | 67 -> QueryUsersReplyReq (QueryUsersReply.parse len s)
(* UDP *)


(* MLDONKEY *)
          | 250 -> mldonkey_extensions len s
          | _ ->
              raise Not_found
        end
    | 0xD4 -> (* 212 *)
        
(*        lprintf "Compressed Message...\n"; *)
        
        if Autoconf.has_zlib then
          let s = Autoconf.zlib__uncompress_string2 (String.sub s 1 (len-1)) in
          let s = Printf.sprintf "%c%s" (char_of_int opcode) s in 
          parse 227 s
        else
          failwith "No Zlib to uncompress packet"
    | _ ->   
        failwith (Printf.sprintf "Unkown opcode %d from server\n" opcode)
  with
    e -> 
      if !CommonOptions.verbose_unknown_messages then begin
          lprintf "Unknown message From server: %s (magic %d)\n"
            (Printexc2.to_string e) magic; 
          let tmp_file = Filename.temp_file "comp" "pak" in
          File.from_string tmp_file s;
          lprintf "Saved unknown packet %s\n" tmp_file; 
          
          dump s;
          lprint_newline ();
        end;
      UnknownReq s
      
let print t =
  begin
    match t with
      ConnectReq t -> Connect.print t
    | SetIDReq t -> SetID.print t
    | AckIDReq t -> AckID.print t
    | MessageReq t -> Message.print t
    | BadProtocolVersionReq -> lprintf "BAD PROTOCOL VERSION"
    | ShareReq t -> Share.print t
    | InfoReq t -> Info.print t
    | ServerListReq t -> ServerList.print t
    | ServerInfoReq t -> ServerInfo.print t
    | QueryReq t -> Query.print t
    | QueryReplyReq t -> QueryReply.print t
    | QueryLocationReq t
      -> QueryLocation.print t
    | QueryLocationReplyReq t
      -> 
        QueryLocationReply.print t
    | QueryIDReq t -> QueryID.print t
    | QueryIDFailedReq t -> QueryIDFailed.print t
    | QueryIDReplyReq t -> QueryIDReply.print t
    | QueryUsersReq t -> QueryUsers.print t
    | QueryUsersReplyReq t -> QueryUsersReply.print t
    | ChatRoomsReq t -> ChatRooms.print t

    | QueryMoreResultsReq -> 
        lprintf "QUERY MORE RESULTS\n"; 
    | Mldonkey_MldonkeyUserReplyReq ->
        lprintf "MLDONKEY USER\n"; 
    | Mldonkey_SubscribeReq (num, lifetime, t) -> 
        lprintf "MLDONKEY SUBSCRIPTION %d FOR %d SECONDS\n" num lifetime; 
        
        Query.print t
    | Mldonkey_NotificationReq (num,t) ->
        lprintf "MLDONKEY NOTIFICATIONS TO %d\n" num; 
        QueryReply.print t
    | Mldonkey_CloseSubscribeReq num ->
        lprintf "MLDONKEY CLOSE SUBSCRIPTION %d\n" num; 
    | UnknownReq s -> 
        let len = String.length s in
        lprintf "UnknownReq:\n";
        lprintf "ascii: [";
        for i = 0 to len - 1 do
          let c = s.[i] in
          let n = int_of_char c in
          if n > 31 && n < 127 then
            lprintf " %c" c
          else
            lprintf "(%d)" n
        done;
        lprintf "]\n";
        lprintf "dec: [";
        for i = 0 to len - 1 do
          let c = s.[i] in
          let n = int_of_char c in
          lprintf "(%d)" n            
        done;
        lprintf "]\n";
  end;
  lprint_newline ()


let bprint oc t =
  begin
    match t with
      ConnectReq t -> Connect.bprint oc t
    | SetIDReq t -> SetID.bprint oc t
    | AckIDReq t -> AckID.bprint oc t
    | MessageReq t -> Message.bprint oc t
    | BadProtocolVersionReq -> Printf.bprintf oc "BAD PROTOCOL VERSION\n"
    | ShareReq t -> Share.bprint oc t
    | InfoReq t -> Info.bprint oc t
    | ServerListReq t -> ServerList.bprint oc t
    | ServerInfoReq t -> ServerInfo.bprint oc t
    | QueryReq t -> Query.bprint oc t
    | QueryReplyReq t -> QueryReply.bprint oc t
    | QueryLocationReq t -> QueryLocation.bprint oc t
    | QueryLocationReplyReq t -> QueryLocationReply.bprint oc t
    | QueryIDReq t -> QueryID.bprint oc t
    | QueryIDFailedReq t -> QueryIDFailed.bprint oc t
    | QueryIDReplyReq t -> QueryIDReply.bprint oc t
    | QueryUsersReq t -> QueryUsers.bprint oc t
    | QueryUsersReplyReq t -> QueryUsersReply.bprint oc t
    | ChatRoomsReq t -> ChatRooms.bprint oc t

    | QueryMoreResultsReq -> 
        Printf.bprintf oc "QUERY MORE RESULTS\n"
    | Mldonkey_MldonkeyUserReplyReq ->
        Printf.bprintf oc "MLDONKEY USER\n"
    | Mldonkey_SubscribeReq (num, lifetime, t) -> 
        Printf.bprintf oc "MLDONKEY SUBSCRIBE %d FOR %d SECONDS\n" num lifetime;
        Query.bprint oc t
    | Mldonkey_NotificationReq (num,t) ->
        Printf.bprintf oc "MLDONKEY NOTIFICATIONS TO %d\n" num; 
        QueryReply.bprint oc t
    | Mldonkey_CloseSubscribeReq num ->
        lprintf "MLDONKEY CLOSE SUBSCRIPTION %d\n" num;
        
    | UnknownReq s -> 
(* let len = String.length s in*)
        Printf.bprintf oc "UnknownReq\n"
(* lprintf "ascii: [";
        for i = 0 to len - 1 do
          let c = s.[i] in
          let n = int_of_char c in
          if n > 31 && n < 127 then
            lprintf " %c" c
          else
            lprintf "(%d)" n
        done;
        lprintf "]\n";
        lprintf "dec: [";
        for i = 0 to len - 1 do
          let c = s.[i] in
          let n = int_of_char c in
          lprintf "(%d)" n            
        done;
        lprintf "]\n";
        lprint_newline ()*)
  end
  
(* Why is this called udp_write ??? It is the normal function to encode messages
  both on UDP and TCP connections !!! *)
  
let write buf t =
  match t with
  | ConnectReq t -> 
      buf_int8 buf 1;
      Connect.write buf t
  | BadProtocolVersionReq ->
      buf_int8 buf 5
  | SetIDReq t -> 
      buf_int8 buf 64;
      SetID.write buf  t
  | AckIDReq t -> 
      buf_int8 buf 20;
      AckID.write buf  t
  | MessageReq t -> 
      buf_int8 buf 56;
      Message.write buf  t
  | ShareReq t -> 
      buf_int8 buf 21;
      Share.write buf  t
  | InfoReq t -> 
      buf_int8 buf 52;
      Info.write buf  t
  | ServerListReq t -> 
      buf_int8 buf 50;
      ServerList.write buf  t
  | ServerInfoReq t -> 
      buf_int8 buf 65;
      ServerInfo.write buf  t
  | QueryReplyReq t ->
      buf_int8 buf 51;
      QueryReply.write buf t
  | QueryReq t -> 
      buf_int8 buf 22;
      Query.write buf t
  | QueryLocationReq t ->
      buf_int8 buf 25;
      QueryLocation.write buf t
  | QueryLocationReplyReq t -> 
      buf_int8 buf 66;
      QueryLocationReply.write buf t
  | QueryIDReq t -> 
      buf_int8 buf 28;
      QueryID.write buf t
  | QueryIDReplyReq t -> 
      buf_int8 buf 53;
      QueryIDReply.write buf t
  | QueryIDFailedReq t -> 
      buf_int8 buf 54;
      QueryIDFailed.write buf t
  | ChatRoomsReq t ->
      buf_int8 buf 57;
      ChatRooms.write buf t
  | UnknownReq s ->
      Buffer.add_string buf s
  | QueryUsersReq t -> 
      buf_int8 buf 26;
      QueryUsers.write buf t
  | QueryUsersReplyReq t -> 
      buf_int8 buf 67;
      QueryUsersReply.write buf t
  | QueryMoreResultsReq ->
      buf_int8 buf 33
      
(**************
mldonkey extensions to the protocol
**************)
  
  | Mldonkey_MldonkeyUserReplyReq ->
      buf_int8 buf 250; (* MLdonkey extensions opcode *)
      buf_int8 buf 1
      
  | Mldonkey_SubscribeReq (num, lifetime, t) ->
      buf_int8 buf 250; (* MLdonkey extensions opcode *)
      buf_int8 buf 2;
      buf_int buf num;
      buf_int buf lifetime;
      Query.write buf t

  | Mldonkey_CloseSubscribeReq num ->
      buf_int8 buf 250; (* MLdonkey extensions opcode *)
      buf_int8 buf 4;
      buf_int buf num;
            
  | Mldonkey_NotificationReq (num,t) ->
      buf_int8 buf 250; (* MLdonkey extensions opcode *)
      buf_int8 buf 3;
      buf_int buf num;
      QueryReply.write_replies buf t

let to_string m =
  let b = Buffer.create 100 in
  bprint b m;
  Buffer.contents b

  (*
let _ =
  let s = "abcdefghijklmnopqrstuvwxyz" in
  let compressed = Autoconf.zlib__compress_string s in
  let ss = Autoconf.zlib__uncompress_string2 compressed in
  lprintf "[%s] <> [%s]\n" s (String.escaped ss);
  assert (s = ss);
  exit 2
  *)