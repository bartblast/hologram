defmodule Hologram.DB.Protocol do
  @moduledoc false

  # TODO(#1696): delete this module once a Postgrex release returns a connection error from a socket
  # call that fails as a connection opens, and require that release. The pool then starts from
  # {Postgrex, opts} again, and the one-off connections through Postgrex.start_link/1.
  #
  # Postgrex's connection module for the pool and the one-off connections, with one change: a
  # connect whose socket fails as it opens returns a connection error instead of raising.
  #
  # Right after the TCP connect, Postgrex matches on the results of :inet.getopts/2 and
  # :inet.setopts/2 in connect/5 and of :inet.peername/1 in handshake/3. A peer that accepts the
  # connection and resets it at once - a proxy or a load balancer with nothing healthy behind it -
  # makes the call the reset lands before return an error, and the match raises a MatchError.
  # DBConnection backs off and tries again after a connect that returns an error, but re-raises one
  # that raises, so the connection crashes and its supervisor counts a restart. Every other callback
  # is Postgrex's own.

  @behaviour DBConnection

  # The steps of Postgrex.Protocol whose failed socket call raises, by the frame the raise comes
  # from, and the name its connection error gives them. connect/5's step covers the getopts before
  # the setopts too - the frame can't tell the two apart.
  @failing_steps %{{:handshake, 3} => "peername", {:connect, 5} => "setopts"}

  @doc """
  Returns the child spec of a connection pool started with the given Postgrex options, as
  Postgrex.child_spec/1 does, with this module as the pool's connection module.
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(opts) do
    # TODO(#1696): Postgrex.child_spec/1 fills in the defaults the same way, through
    # Postgrex.Utils.default_opts/1, which is public but undocumented.
    DBConnection.child_spec(__MODULE__, Postgrex.Utils.default_opts(opts))
  end

  @doc """
  Runs the given function and returns what it returns, unless it raised because one of Postgrex's
  socket calls failed as the connection opened - see the comment at the top. It then closes the
  socket left open and returns `{:error, %DBConnection.ConnectionError{}}`, the error a connect
  that fails anywhere else returns. Every other exception is raised again.

  The socket is the port Postgrex's connect linked to the calling process, and nothing else would
  close it: the state that names it never comes back. Under the `inet_backend: :socket` kernel
  setting a socket isn't a port, so nothing is found to close, and the socket stays open for as
  long as the calling process lives.
  """
  @spec rescue_peer_reset((-> result)) :: result | {:error, DBConnection.ConnectionError.t()}
        when result: any
  def rescue_peer_reset(fun) do
    ports_before = linked_tcp_ports()

    try do
      fun.()
    rescue
      error in MatchError ->
        case failed_step(error, __STACKTRACE__) do
          {step, reason} ->
            close_sockets(linked_tcp_ports() -- ports_before)

            message = "tcp #{step}: #{:inet.format_error(reason)} - #{inspect(reason)}"

            {:error, DBConnection.ConnectionError.exception(message)}

          nil ->
            reraise error, __STACKTRACE__
        end
    end
  end

  @doc """
  Starts a connection pool with the given Postgrex options, linked to the caller, as
  Postgrex.start_link/1 does, with this module as the pool's connection module.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    # TODO(#1696): see child_spec/1.
    DBConnection.start_link(__MODULE__, Postgrex.Utils.default_opts(opts))
  end

  @impl DBConnection
  def connect(opts) do
    rescue_peer_reset(fn -> Postgrex.Protocol.connect(opts) end)
  end

  @impl DBConnection
  defdelegate checkout(state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate disconnect(error, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_begin(opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_close(query, opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_commit(opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_deallocate(query, cursor, opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_declare(query, params, opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_execute(query, params, opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_fetch(query, cursor, opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_prepare(query, opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_rollback(opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate handle_status(opts, state), to: Postgrex.Protocol

  @impl DBConnection
  defdelegate ping(state), to: Postgrex.Protocol

  defp close_sockets(ports) do
    # :gen_tcp.close/1 rather than Port.close/1: it takes the port's exit message out of the
    # mailbox after closing it, so none is left for a process that traps exits, as Postgrex's
    # connect makes the caller.
    Enum.each(ports, &:gen_tcp.close/1)
  end

  defp failed_step(%MatchError{term: {:error, reason}}, [
         {Postgrex.Protocol, fun, arity, _location} | _callers
       ])
       when is_atom(reason) do
    case Map.fetch(@failing_steps, {fun, arity}) do
      {:ok, step} -> {step, reason}
      :error -> nil
    end
  end

  defp failed_step(_error, _stacktrace), do: nil

  defp linked_tcp_ports do
    {:links, links} = Process.info(self(), :links)

    Enum.filter(links, &(is_port(&1) and Port.info(&1, :name) == {:name, ~c"tcp_inet"}))
  end
end
