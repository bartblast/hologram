defmodule Hologram.Realtime.Tombstone do
  @moduledoc false

  use GenServer

  @boot_sync_timeout_ms 5_000
  @gossip_topic "hologram:gossip:tombstones"
  @table_name :hologram_tombstones
  @tombstone_ttl_ms 72 * 60 * 60 * 1000

  @doc """
  Returns the name of the ETS table that backs the tombstone store.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns the PubSub topic used for cluster-wide gossip of tombstone inserts.
  """
  @spec gossip_topic() :: String.t()
  def gossip_topic, do: @gossip_topic

  @doc """
  Inserts a tombstone for the given `key` with the given `created_at`
  timestamp (in milliseconds).

  Accepts both key shapes:

    * Binding-level - `{identity, channel, cid}`
    * Channel-wide - `{identity, channel}`

  where `identity` is one of `{:instance, I}`, `{:session, S}`, or
  `{:user, U}`. The two shapes have different arities and are keyed
  independently in ETS, so both can coexist at the same identity level.
  """
  @spec insert(tuple, integer) :: :ok
  def insert(key, created_at) do
    GenServer.call(__MODULE__, {:insert, key, created_at})
  end

  @doc """
  Starts the tombstone store process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the tombstone TTL in milliseconds.
  """
  @spec tombstone_ttl_ms() :: pos_integer
  def tombstone_ttl_ms, do: @tombstone_ttl_ms

  @impl GenServer
  def init(opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    Phoenix.PubSub.subscribe(Hologram.PubSub, @gossip_topic)

    boot_sync_timeout_ms =
      Keyword.get(opts, :boot_sync_timeout_ms, @boot_sync_timeout_ms)

    schedule_sweep()

    {:ok, %{}, {:continue, {:boot_sync, boot_sync_timeout_ms}}}
  end

  @impl GenServer
  def handle_call({:insert, key, created_at}, _from, state) do
    merge_insert(key, created_at)

    Phoenix.PubSub.broadcast_from(
      Hologram.PubSub,
      self(),
      @gossip_topic,
      {:insert, key, created_at}
    )

    {:reply, :ok, state}
  end

  # Boot-sync runs here rather than in init/1 so the blocking wait for peer
  # replies doesn't stall the supervision tree (and thus app/endpoint
  # readiness) for the full timeout on every boot. The ETS table and gossip
  # subscription are established in init/1, so direct readers and live gossip
  # are unaffected during this catch-up window.
  @impl GenServer
  def handle_continue({:boot_sync, boot_sync_timeout_ms}, state) do
    Phoenix.PubSub.broadcast_from(
      Hologram.PubSub,
      self(),
      @gossip_topic,
      {:sync_request, self()}
    )

    collect_sync_replies(System.monotonic_time(:millisecond) + boot_sync_timeout_ms)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:insert, key, created_at}, state) do
    merge_insert(key, created_at)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:purge, key}, state) do
    :ets.delete(@table_name, key)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:sweep_expired, state) do
    delete_expired()
    schedule_sweep()

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:sync_request, requester_pid}, state) do
    entries = :ets.tab2list(@table_name)
    send(requester_pid, {:sync_reply, entries})

    {:noreply, state}
  end

  defp collect_sync_replies(deadline) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:sync_reply, entries} ->
        Enum.each(entries, fn {key, created_at} -> merge_insert(key, created_at) end)
        collect_sync_replies(deadline)
    after
      remaining_ms -> :ok
    end
  end

  defp delete_expired do
    cutoff = System.system_time(:millisecond) - @tombstone_ttl_ms

    match_spec = [
      {{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}
    ]

    :ets.select_delete(@table_name, match_spec)
  end

  defp merge_insert(key, created_at) do
    case :ets.lookup(@table_name, key) do
      [{^key, existing_at}] when existing_at >= created_at ->
        :ok

      _other ->
        :ets.insert(@table_name, {key, created_at})
    end
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep_expired, @tombstone_ttl_ms)
  end
end
