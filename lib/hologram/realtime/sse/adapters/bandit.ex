defmodule Hologram.Realtime.SSE.Adapters.Bandit do
  @moduledoc false

  # Bandit runs the plug in a process of its own over HTTP/2 and in the process that owns
  # the connection over HTTP/1.1, so a departed client reaches the stream differently on
  # each. Everything here is matched by shape because Hologram doesn't depend on Bandit - a
  # Bandit that reshapes these internals falls through to noticing through the heartbeat.

  @behaviour Hologram.Realtime.SSE.Adapter

  # Bandit delivers a client's HTTP/2 stream reset to the stream's process, which is the
  # pump's. Left unhandled it would be swallowed and the stream would live on until a
  # heartbeat write fails.
  @impl Hologram.Realtime.SSE.Adapter
  def handle_message({:bandit, {:rst_stream, _error_code}}), do: :closed

  # Over HTTP/1.1 the pump watches its own socket (see watch/1), so a closed tab arrives
  # here rather than waiting for a heartbeat write to fail. The message is handed back
  # before closing: Thousand Island owns the socket and ends the connection on this
  # message, and without it would hold the dead connection open until its read timeout.
  def handle_message({closed, _socket} = message) when closed in [:ssl_closed, :tcp_closed] do
    send(self(), message)
    :closed
  end

  # Anything else from the socket ends the stream too. An SSE client sends nothing once
  # the stream is open, so bytes or an error here mean the connection is no longer one.
  # Handed back for the same reason, and so that bytes start the connection's next
  # request rather than being lost.
  def handle_message({event, _socket, _payload} = message)
      when event in [:ssl, :ssl_error, :tcp, :tcp_error] do
    send(self(), message)
    :closed
  end

  def handle_message(_message), do: :ignore

  # Over HTTP/1.1 Bandit reads nothing from the socket while the plug runs, so a closed tab
  # goes unnoticed until a heartbeat write fails. Asking for the socket's next event makes
  # the close arrive in the pump's mailbox instead. Over HTTP/2 there is nothing to arm -
  # the connection process reports a reset on its own.
  @impl Hologram.Realtime.SSE.Adapter
  def watch(%Plug.Conn{
        adapter:
          {Bandit.Adapter,
           %{
             transport: %{
               __struct__: Bandit.HTTP1.Socket,
               socket: %{socket: raw_socket, transport_module: transport_module}
             }
           }}
      }) do
    transport_module.setopts(raw_socket, active: :once)
    :ok
  end

  def watch(_conn), do: :ok
end
