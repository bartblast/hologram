defmodule Hologram.DB.Listener do
  @moduledoc false

  # A connection that listens for announcements, outside the pool: LISTEN belongs to one session
  # for as long as it listens, which a pooled connection cannot promise.
  #
  # Held for as long as its session lasts (see Hologram.DB.Config.held_connection_opts/1). While the
  # database refuses connections it keeps trying, and a process listening through it meanwhile is
  # answered :eventually between two tries - its channel is registered here and sent to the server
  # once the session opens. A try against a host that drops packets rather than refusing them
  # blocks this process until the connect timeout, and a listen call made meanwhile exits after its
  # 5 seconds. A session that is lost ends this process, and so does a LISTEN the server leaves
  # unanswered for 4 seconds (see @query_timeout_ms). Whatever listens through it is restarted
  # beside it and listens again as it starts. Reconnecting in place would leave that process
  # waiting on announcements sent while the session was gone, which nothing would tell it about.
  #
  # Its own module rather than Postgrex.Notifications started to reconnect. That one sends UNLISTEN
  # when the last process listening on a channel exits, without checking for a session - and with
  # none it crashes, taking down this connection whenever its listener dies while the database is
  # away. Nothing is ever unlistened here: a channel nobody listens on any more costs a notification
  # dropped on arrival, and the processes listening come back to the same channels.
  #
  # It speaks the call Postgrex.Notifications.listen/2 makes, so a process may listen through
  # either function.

  @behaviour Postgrex.SimpleConnection

  alias Hologram.DB.Config
  alias Postgrex.SimpleConnection

  # The longest identifier PostgreSQL keeps whole - a longer channel name is truncated, and its
  # notifications arrive under a name nobody listens on.
  @max_channel_bytes 63

  # How long a listen call may wait for this process to answer - longer than a LISTEN may take
  # only while it is busy connecting or pinging.
  @listen_timeout_ms :timer.seconds(5)

  # How long the server may take to answer a LISTEN before this process is killed. Postgrex waits
  # for an answer with no bound of its own, and this process does nothing else meanwhile, so a link
  # that went silent with a LISTEN in flight would hold it, and every process listening through it:
  # the idle ping cannot run. Once the server's side acknowledged the LISTEN, nothing is left for
  # the operating system to resend and it never gives up on the socket - held for good. Otherwise
  # it gives up only after resending for about 15 minutes on Linux. The replay sent as the session
  # opens is bounded too, though nobody waits on it.
  #
  # A healthy server answers well within it. A session's first LISTEN also reads through the
  # notifications still queued, which is slow only when the queue is huge.
  #
  # Below a listen call's timeout, so a caller waiting on the answer sees this process end rather
  # than giving up first. A rest_for_one supervisor then gets this process's exit before the
  # caller's and restarts both once, rather than the caller on its own and then both again. This
  # bound starts once the call is picked up, a moment after the caller's, which keeps the order
  # while calls come one at a time - each process listening through it makes one as it starts.
  @query_timeout_ms @listen_timeout_ms - :timer.seconds(1)

  @doc """
  Returns the child spec of the connection, started with the given options (see start_link/1).
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Listens on the given channel through the given connection, on behalf of the caller.

  Returns `{:ok, ref}` once the server listens, or `{:eventually, ref}` when the session has not
  opened yet - the server is told as soon as it does. Each notification on the channel then
  arrives as `{:notification, connection, ref, channel, payload}`, until the caller exits.

  Exits when the connection has not answered within 5 seconds. A LISTEN the server leaves
  unanswered for 4 seconds ends the connection, which exits the caller as well.

  Raises ArgumentError for a channel name the server would not listen on as given: an empty one, one
  with a null byte, or one over 63 bytes, which the server truncates.
  """
  @spec listen(GenServer.server(), String.t()) :: {:ok, reference} | {:eventually, reference}
  def listen(connection, channel) when is_binary(channel) do
    cond do
      channel == "" ->
        raise ArgumentError, "a channel name cannot be empty"

      String.contains?(channel, <<0>>) ->
        raise ArgumentError, "a channel name cannot contain null bytes, got: #{inspect(channel)}"

      byte_size(channel) > @max_channel_bytes ->
        raise ArgumentError,
              "a channel name cannot exceed #{@max_channel_bytes} bytes, got #{byte_size(channel)} bytes: #{inspect(channel)}"

      true ->
        SimpleConnection.call(connection, {:listen, channel}, @listen_timeout_ms)
    end
  end

  @doc """
  Starts the connection, linked to the caller.

  `:name` registers it. Every other option overrides Hologram.DB.Config.held_connection_opts/1.
  It returns without waiting on the server.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    SimpleConnection.start_link(__MODULE__, nil, Config.held_connection_opts(opts))
  end

  @impl SimpleConnection
  def handle_call({:listen, channel}, {pid, _tag} = from, state) do
    ref = Process.monitor(pid)

    state = %{
      state
      | channels: Map.update(state.channels, channel, %{ref => pid}, &Map.put(&1, ref, pid)),
        refs: Map.put(state.refs, ref, channel)
    }

    if state.connected do
      # Sent again when the server already listens on the channel, which is harmless and happens
      # once per process starting to listen.
      query(listen_statement([channel]), %{state | from: from, ref: ref})
    else
      SimpleConnection.reply(from, {:eventually, ref})

      {:noreply, state}
    end
  end

  # SimpleConnection keeps the idle ping off after a connect (it drops what handle_connect/1
  # returns), so without the message below a session nobody calls would never be pinged, and a link
  # that went silent would never be noticed.
  @impl SimpleConnection
  def handle_connect(state) do
    send(self(), :arm_ping)

    state = %{state | connected: true}

    case Map.keys(state.channels) do
      [] -> {:noreply, state}
      channels -> query(listen_statement(channels), state)
    end
  end

  @impl SimpleConnection
  @spec handle_disconnect(map) :: no_return
  def handle_disconnect(state) do
    disarm(state)
    Config.end_lost_session!()
  end

  @impl SimpleConnection
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {channel, refs} ->
        listeners = Map.delete(state.channels[channel], ref)

        channels =
          if listeners == %{},
            do: Map.delete(state.channels, channel),
            else: Map.put(state.channels, channel, listeners)

        {:noreply, %{state | channels: channels, refs: refs}}
    end
  end

  # :arm_ping, and anything else - the connection traps exits.
  def handle_info(_message, state), do: {:noreply, state}

  @impl SimpleConnection
  def handle_result(results_or_error, state) do
    handle_answer(results_or_error, disarm(state))
  end

  @impl SimpleConnection
  def init(nil) do
    {:ok, %{channels: %{}, connected: false, from: nil, ref: nil, refs: %{}, timer: nil}}
  end

  @impl SimpleConnection
  def notify(channel, payload, state) do
    for {ref, pid} <- Map.get(state.channels, channel, %{}) do
      send(pid, {:notification, self(), ref, channel, payload})
    end

    :ok
  end

  # A kill that fired just before the cancel reaches this process before the cancel returns, since
  # the timer server sends it, so this process never carries on with one pending.
  defp disarm(%{timer: nil} = state), do: state

  defp disarm(state) do
    :timer.cancel(state.timer)

    %{state | timer: nil}
  end

  # A LISTEN the server refused leaves this connection deaf to that channel, which is what it must
  # never be while it stays up.
  defp handle_answer(%Postgrex.Error{} = error, _state), do: raise(error)

  defp handle_answer(_results, %{from: nil} = state), do: {:noreply, state}

  defp handle_answer(_results, state) do
    SimpleConnection.reply(state.from, {:ok, state.ref})

    {:noreply, %{state | from: nil, ref: nil}}
  end

  defp listen_statement(channels) do
    Enum.map_join(channels, "; ", &~s(LISTEN "#{String.replace(&1, ~s("), ~s(""))}"))
  end

  # Sends the statement with the kill armed against an answer that never comes (see
  # @query_timeout_ms). Every query this process sends goes through here.
  defp query(statement, state) do
    {:ok, timer} = :timer.kill_after(@query_timeout_ms)

    {:query, statement, %{state | timer: timer}}
  end
end
