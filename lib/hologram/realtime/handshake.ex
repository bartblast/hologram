defmodule Hologram.Realtime.Handshake do
  @moduledoc false

  use GenServer

  @gossip_topic "hologram:gossip:sse_handshakes"
  @sse_handshake_boot_sync_timeout_ms 5_000
  @sse_handshake_stash_ttl_ms 60_000
  @table_name :hologram_sse_handshakes

  @doc """
  Returns the name of the ETS table that backs the handshake stash.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns the PubSub topic used for cluster-wide gossip of stash inserts.
  """
  @spec gossip_topic() :: String.t()
  def gossip_topic, do: @gossip_topic

  @doc """
  Stashes a handshake entry locally and broadcasts it on the gossip topic so
  peer nodes can mirror it into their own stash.

  `identity` is the `{instance_id, session_id, user_id}` tuple of the POSTing
  client, used at GET-time consume to verify the consumer is the same client
  that completed the POST.

  The stashed entry is `{handshake_id, validated_bindings, instance_id,
  session_id, user_id, expires_at}` (flat ETS tuple); the gossip message
  mirrors the same shape under the `:insert` tag.
  """
  @spec insert(
          String.t(),
          [{{any, String.t()}, term | nil}],
          {String.t() | nil, term | nil, term | nil},
          integer
        ) :: :ok
  def insert(handshake_id, validated_bindings, identity, expires_at) do
    GenServer.call(
      __MODULE__,
      {:insert, handshake_id, validated_bindings, identity, expires_at}
    )
  end

  @doc """
  Starts the handshake stash process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sweeps the ETS table and deletes every entry whose `expires_at` is in the
  past. Called periodically by the GenServer's internal timer; also exposed
  as a synchronous API so callers (and tests) can trigger a sweep on demand.
  """
  @spec sweep_expired() :: :ok
  def sweep_expired do
    GenServer.call(__MODULE__, :sweep_expired)
  end

  @impl GenServer
  def init(opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    Phoenix.PubSub.subscribe(Hologram.PubSub, @gossip_topic)

    boot_sync_timeout_ms =
      Keyword.get(opts, :boot_sync_timeout_ms, @sse_handshake_boot_sync_timeout_ms)

    Phoenix.PubSub.broadcast_from(
      Hologram.PubSub,
      self(),
      @gossip_topic,
      {:sync_request, self()}
    )

    collect_sync_replies(System.monotonic_time(:millisecond) + boot_sync_timeout_ms)

    schedule_sweep()

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call(
        {:insert, handshake_id, validated_bindings, {instance_id, session_id, user_id},
         expires_at},
        _from,
        state
      ) do
    :ets.insert(
      @table_name,
      {handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at}
    )

    Phoenix.PubSub.broadcast_from(
      Hologram.PubSub,
      self(),
      @gossip_topic,
      {:insert, handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at}
    )

    {:reply, :ok, state}
  end

  def handle_call(:sweep_expired, _from, state) do
    delete_expired()

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(
        {:insert, handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at},
        state
      ) do
    :ets.insert(
      @table_name,
      {handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at}
    )

    {:noreply, state}
  end

  def handle_info(:sweep_expired, state) do
    delete_expired()
    schedule_sweep()

    {:noreply, state}
  end

  def handle_info({:sync_request, requester_pid}, state) do
    entries = :ets.tab2list(@table_name)
    send(requester_pid, {:sync_reply, entries})

    {:noreply, state}
  end

  defp collect_sync_replies(deadline) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:sync_reply, entries} ->
        :ets.insert(@table_name, entries)
        collect_sync_replies(deadline)
    after
      remaining_ms -> :ok
    end
  end

  defp delete_expired do
    now = System.system_time(:millisecond)

    match_spec = [
      {{:_, :_, :_, :_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ]

    :ets.select_delete(@table_name, match_spec)
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep_expired, @sse_handshake_stash_ttl_ms)
  end
end
