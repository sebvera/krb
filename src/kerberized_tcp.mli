open! Core
open Async
open Import

type 'a with_krb_args =
  ?cred_cache:Cred_cache.t
  (** This defaults to [Cred_cache.default] for a [TGT] key source and a new MEMORY cache
      for a [Keytab] key source. *)
  -> ?on_connection:(Socket.Address.Inet.t -> Server_principal.t -> [ `Accept | `Reject ])
  (** [on_connection] gets passed the ip of the server and principal the server is running
      as. Allows checking that the server is who we expected it to be.

      Similar functionality can be implemented by validating the [Principal.Name.t]
      returned by [connect] yourself, however if [on_connection] returns [`Reject] the
      client will be rejected early, without fully establishing a connection.
  *)
  -> krb_mode:Mode.Client.t
  -> 'a

type 'a with_connect_args =
  (Socket.Address.Inet.t Tcp.Where_to_connect.t -> 'a) with_krb_args
    Tcp.with_connect_options

val connect : (Kerberized_rw.t * Server_principal.t) Deferred.Or_error.t with_connect_args

val with_connection
  : ((Kerberized_rw.t -> Server_principal.t -> 'a Deferred.t) -> 'a Deferred.Or_error.t)
      with_connect_args

(** Arguments passed through to [Tcp.Server.create].  See [Async.Tcp] for documentation *)
type 'a async_tcp_server_args =
  ?max_connections:int
  -> ?backlog:int
  -> ?drop_incoming_connections:bool
  -> ?buffer_age_limit:Writer.buffer_age_limit
  -> 'a

module Server : sig
  type ('a, 'b) t = ('a, 'b) Tcp.Server.t


  (** Create a TCP server. Unlike an un-kerberized TCP server, this will read and write
      some bytes from/to the underlying socket before returning a [t]. *)
  val create
    : (?on_kerberos_error:
        [ `Call of Socket.Address.Inet.t -> exn -> unit | `Ignore | `Raise ]
       (** [on_kerberos_error] gets called for any kerberos related errors that occur
           during setup of a connection. This includes failure to de/encrypt messages
           during the setup phase, invalid service tickets sent by the client, etc. It
           defaults to logging via [Log.Global.error]. *)
       -> ?on_handshake_error:
         [ `Call of Socket.Address.Inet.t -> exn -> unit | `Ignore | `Raise ]
       (** [on_handshake_error] gets called for any non-kerberos related errors that occur
           during setup of a connection. This includes connectivity errors and version
           negotiation errors. It defaults to [`Ignore] *)
       -> ?on_handler_error:
         [ `Call of Socket.Address.Inet.t -> exn -> unit | `Ignore | `Raise ]
       (** [on_handler_error] gets called for any errors that occur within the handler
           function passed into [Server.create]. This includes any exceptions raised by the
           handler function as well as errors in de/encrypting messages. It defaults to
           [`Raise]. *)
       -> ?on_connection:
         (Socket.Address.Inet.t -> Client_principal.t -> [ `Accept | `Reject ])
       (** [on_connection] gets passed the ip of the client and the principal the client
           is authenticated as. [`Reject] will close the connection.

           See the comment on the [on_connection] argument of [connect] for why you might
           use this instead of validating the returned [Client_identity.t] yourself.

           Furthermore, the error will propagate to the client as part of the connection
           establishment protocol.  This allows the client to get a more meaningful message
           ("server rejected client principal or address" instead of something like "connection
           closed").
       *)
       -> krb_mode:Mode.Server.t
       -> Tcp.Where_to_listen.inet
       -> (Client_principal.t
           -> Socket.Address.Inet.t
           -> Reader.t
           -> Writer.t
           -> unit Deferred.t)
       -> (Socket.Address.Inet.t, int) t Deferred.Or_error.t)
        async_tcp_server_args
end

module Internal : sig
  val connect
    : (?override_supported_versions:int list
       -> ?cred_cache:Cred_cache.t
       -> ?on_connection:
         (Socket.Address.Inet.t -> Server_principal.t -> [ `Accept | `Reject ])
       -> krb_mode:Mode.Client.t
       -> Socket.Address.Inet.t Tcp.Where_to_connect.t
       -> Protocol.Connection.t Deferred.Or_error.t)
        Tcp.with_connect_options

  module Endpoint : sig
    val create
      :  Server_key_source.t
      -> (Principal.t
          * (unit
             -> [> `Service of Keytab.t | `User_to_user_via_tgt of Internal.Credentials.t ]
                  Deferred.Or_error.t))
           Deferred.Or_error.t
  end

  module Server : sig
    type 'connection handle_client :=
      Socket.Address.Inet.t -> 'connection -> unit Deferred.t

    type ('principal, 'r) krb_args :=
      ?on_kerberos_error:
        [ `Call of Socket.Address.Inet.t -> exn -> unit | `Ignore | `Raise ]
      -> ?on_handshake_error:
           [ `Call of Socket.Address.Inet.t -> exn -> unit | `Ignore | `Raise ]
      -> ?on_handler_error:
           [ `Call of Socket.Address.Inet.t -> exn -> unit | `Ignore | `Raise ]
      -> ?on_connection:(Socket.Address.Inet.t -> 'principal -> [ `Accept | `Reject ])
      -> krb_mode:Mode.Server.t
      -> 'r

    type ('principal, 'connection) serve :=
      ( 'principal
      , Tcp.Where_to_listen.inet
      -> 'connection handle_client
      -> (Socket.Address.Inet.t, int) Server.t Deferred.Or_error.t )
        krb_args
        async_tcp_server_args

    val create_handler
      : ( Client_principal.t
        , Protocol.Connection.t handle_client
          -> (Socket.Address.Inet.t -> Reader.t -> Writer.t -> unit Deferred.t)
               Deferred.Or_error.t )
          krb_args

    val create : (Client_principal.t, Protocol.Connection.t) serve

    module Krb_or_anon_conn : sig
      type t =
        | Krb of Protocol.Connection.t
        | Anon of (Reader.t * Writer.t)
    end

    (** This is a bit misleading because it doesn't work with an unkerberized tcp client.
        It is in an [Internal] module because it is useful for implementing
        kerberized rpc [serve_with_anon].

        The [create_with_anon] server peeks the first few bytes to check if the client is
        sending a kerberos protocol header. If the unkerberized tcp client is expecting
        the server to send some initial bytes, it will be waiting until something
        presumably times out because the server is waiting for the client to send bytes
        also. *)
    val create_with_anon : (Client_principal.t option, Krb_or_anon_conn.t) serve
  end
end
