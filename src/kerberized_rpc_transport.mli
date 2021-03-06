open! Core
open Async
open Import

module Tcp : sig
  (** When we accept or initiate a connection, we get a [Protocol.Connection.t], which
      gives (a) the ability to send/receive bytes, and (b) some kerberos-specific
      operations like [read_krb_cred].

      (a) is turned into an rpc-transport.
      (b) is [Krb_ops]. *)
  module Krb_ops : sig
    type t

    val my_principal : t -> Principal.Name.t
    val peer_principal : t -> Principal.Name.t
  end

  type on_error :=
    [ `Call of Socket.Address.Inet.t -> exn -> unit
    | `Ignore
    | `Raise
    ]

  (** refer to [Kerberized_tcp] and [Kerberized_rpc] for details on these arguments. *)
  val serve
    :  ?max_message_size:int
    -> (?on_kerberos_error:on_error
        -> ?on_handshake_error:on_error
        -> ?on_handler_error:on_error
        -> ?on_connection:
          (Socket.Address.Inet.t -> Client_principal.t -> [ `Accept | `Reject ])
        -> ?on_done_with_internal_buffer:[ `Do_nothing | `Zero ]
        -> where_to_listen:Tcp.Where_to_listen.inet
        -> krb_mode:Mode.Server.t
        -> (Socket.Address.Inet.t -> Rpc.Transport.t -> Krb_ops.t -> unit Deferred.t)
        -> (Socket.Address.Inet.t, int) Tcp.Server.t Deferred.Or_error.t)
         Kerberized_tcp.async_tcp_server_args

  (** refer to [Kerberized_tcp] and [Kerberized_rpc] for details on these arguments. *)
  val serve_with_anon
    :  ?max_message_size:int
    -> (?on_kerberos_error:on_error
        -> ?on_handshake_error:on_error
        -> ?on_handler_error:on_error
        -> ?on_connection:
          (Socket.Address.Inet.t -> Client_principal.t option -> [ `Accept | `Reject ])
        -> ?on_done_with_internal_buffer:[ `Do_nothing | `Zero ]
        -> where_to_listen:Tcp.Where_to_listen.inet
        -> krb_mode:Mode.Server.t
        -> (Socket.Address.Inet.t
            -> Rpc.Transport.t
            -> Krb_ops.t option
            -> unit Deferred.t)
        -> (Socket.Address.Inet.t, int) Tcp.Server.t Deferred.Or_error.t)
         Kerberized_tcp.async_tcp_server_args

  (** refer to [Kerberized_tcp] and [Kerberized_rpc] for details on these arguments. *)
  val create_handler
    :  ?max_message_size:int
    -> ?on_kerberos_error:on_error
    -> ?on_handshake_error:on_error
    -> ?on_handler_error:on_error
    -> ?on_connection:
         (Socket.Address.Inet.t -> Client_principal.t -> [ `Accept | `Reject ])
    -> ?on_done_with_internal_buffer:[ `Do_nothing | `Zero ]
    -> krb_mode:Mode.Server.t
    -> (Socket.Address.Inet.t -> Rpc.Transport.t -> Krb_ops.t -> unit Deferred.t)
    -> (Socket.Address.Inet.t -> Reader.t -> Writer.t -> unit Deferred.t)
         Deferred.Or_error.t

  (** refer to [Kerberized_tcp] and [Kerberized_rpc] for details on these arguments. *)
  val client
    :  ?max_message_size:int
    -> ?timeout:Time_ns.Span.t
    -> ?cred_cache:Cred_cache.t
    -> ?buffer_age_limit:Writer.buffer_age_limit
    -> ?on_connection:
         (Socket.Address.Inet.t -> Server_principal.t -> [ `Accept | `Reject ])
    -> ?on_done_with_internal_buffer:[ `Do_nothing | `Zero ]
    -> ?krb_mode:Mode.Client.t
    -> Tcp.Where_to_connect.inet
    -> (Rpc.Transport.t * Krb_ops.t) Deferred.Or_error.t
end

module Internal : sig
  module Tcp : sig
    module Krb_ops : sig
      type t = Tcp.Krb_ops.t

      val make_krb_cred
        :  t
        -> forwardable:bool
        -> Internal.Auth_context.Krb_cred.t Deferred.Or_error.t

      val read_krb_cred
        :  t
        -> Internal.Auth_context.Krb_cred.t
        -> Internal.Cred_cache.t Deferred.Or_error.t

      val can_forward_creds : t -> bool
    end

    val client
      :  ?override_supported_versions:int list
      -> ?max_message_size:int
      -> ?timeout:Time_ns.Span.t
      -> ?cred_cache:Cred_cache.t
      -> ?buffer_age_limit:Writer.buffer_age_limit
      -> ?on_connection:
           (Socket.Address.Inet.t -> Server_principal.t -> [ `Accept | `Reject ])
      -> ?on_done_with_internal_buffer:[ `Do_nothing | `Zero ]
      -> ?krb_mode:Mode.Client.t
      -> Async.Tcp.Where_to_connect.inet
      -> (Rpc.Transport.t * Krb_ops.t) Deferred.Or_error.t
  end
end
