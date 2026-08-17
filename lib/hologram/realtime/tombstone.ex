defmodule Hologram.Realtime.Tombstone do
  @moduledoc false

  use GenServer

  alias Hologram.Realtime.Gossip

  @gossip_topic "hologram:gossip:tombstones"

  # Decoupled from the TTL on purpose: sweeping only once per TTL would let an
  # entry inserted just after a sweep survive for almost another full TTL past
  # expiry (~2x TTL retention). A shorter interval bounds retention to roughly
  # TTL + this interval, so the working set stays close to the documented
  # `rate × TTL` even under heavy tombstone-write traffic.
  @sweep_interval_ms 30 * 60 * 1000

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
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    Phoenix.PubSub.subscribe(Hologram.PubSub, @gossip_topic)

    # Peers are asked for what they hold, and whatever they send back merges as it
    # arrives. Nothing is waited for, so this process serves inserts from the moment it
    # starts, and readers hitting the table meanwhile see the same catch-up window they
    # always have - a tombstone a peer has not sent yet is simply not there yet.
    Gossip.request_sync(@gossip_topic)

    # The ask above reaches the nodes connected right now. A node that connects later -
    # one still joining as this one boots, or a peer coming back - was never asked, and
    # monitoring reports only joins that happen from here on, so this is the only signal
    # that such a node exists.
    :net_kernel.monitor_nodes(true)

    schedule_sweep()

    {:ok, %{}}
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
  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:nodeup, node}, state) do
    # Asked in both directions on purpose. This node asks the newcomer because a peer
    # that went away and came back can hold what this one is missing, and the newcomer
    # asks this node through the same handler on its own side.
    Gossip.request_sync_from(node, @gossip_topic)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:sync_reply, tombstones}, state) do
    Enum.each(tombstones, fn {key, created_at} -> merge_insert(key, created_at) end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:sync_request, requester_pid}, state) do
    Gossip.reply_to_sync_request(@table_name, requester_pid)

    {:noreply, state}
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
    Process.send_after(self(), :sweep_expired, @sweep_interval_ms)
  end
end
