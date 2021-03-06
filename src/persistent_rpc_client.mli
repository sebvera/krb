open! Core
open! Async

(** An instantiation of [Persistent_connection] for creating persistent kerberized rpc
    connections *)

include
  Persistent_connection.S
  with type conn = Rpc.Connection.t
   and type address = Host_and_port.t

(** Arguments passed through to [Persistent_connection.Rpc.create].
    See [Persistent_connection] for documentation. *)
type 'a persistent_connection_args =
  server_name:string
  -> ?log:Log.t
  -> ?on_event:(Event.t -> unit Deferred.t)
  -> ?retry_delay:(unit -> Time.Span.t)
  -> 'a

val create'
  : (krb_mode:Mode.Client.t
     -> ?bind_to_address:Unix.Inet_addr.t
     -> ?implementations:(Server_principal.t -> _ Rpc.Connection.Client_implementations.t)
     -> ?description:Info.t
     -> ?cred_cache:Cred_cache.t
     -> ?on_connection:
       (Socket.Address.Inet.t -> Server_principal.t -> [ `Accept | `Reject ])
     -> (unit -> Host_and_port.t Deferred.Or_error.t)
     -> t)
      Kerberized_rpc.async_rpc_args
      persistent_connection_args
