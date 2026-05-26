defmodule Hologram.Realtime.Handshake do
  @moduledoc false

  use GenServer

  alias Hologram.Realtime.Gossip

  @boot_sync_timeout_ms 5_000
  @gossip_topic "hologram:gossip:sse_handshakes"
  @server_wait_ms 500
  @stash_ttl_ms 60_000
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
  client, used at GET-time redemption to verify the redeemer is the same client
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
  Looks up a stashed handshake entry by `handshake_id` and returns its
  `validated_bindings` and identity tuple. If the entry is not yet in the
  local ETS (the gossip from a peer has not arrived yet), the caller is
  registered as a waiter for up to `timeout` milliseconds. Replies `:error`
  if the entry never lands within the wait window.
  """
  @spec redeem(String.t(), pos_integer) ::
          {:ok, [{{any, String.t()}, term | nil}], {String.t() | nil, term | nil, term | nil}}
          | :error
  def redeem(handshake_id, timeout) do
    GenServer.call(__MODULE__, {:redeem, handshake_id, timeout}, timeout + 1_000)
  end

  @doc """
  Returns the GET-side wait budget (in milliseconds) for `redeem/2` when the
  caller does not pass an explicit timeout. Covers the worst legitimate
  cross-region gossip race with margin.
  """
  @spec server_wait_ms() :: pos_integer
  def server_wait_ms, do: @server_wait_ms

  @doc """
  Starts the handshake stash process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the per-entry stash TTL in milliseconds. Used by callers of `insert/4`
  to compute `expires_at`, and by the GenServer's internal sweep timer.
  """
  @spec stash_ttl_ms() :: pos_integer
  def stash_ttl_ms, do: @stash_ttl_ms

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
      Keyword.get(opts, :boot_sync_timeout_ms, @boot_sync_timeout_ms)

    schedule_sweep()

    {:ok, %{waiters: %{}}, {:continue, {:boot_sync, boot_sync_timeout_ms}}}
  end

  @impl GenServer
  def handle_call(
        {:insert, handshake_id, validated_bindings, {instance_id, session_id, user_id} = identity,
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

    new_state = notify_waiters(state, handshake_id, validated_bindings, identity)

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:redeem, handshake_id, timeout}, from, state) do
    now = System.system_time(:millisecond)

    case :ets.lookup(@table_name, handshake_id) do
      [{^handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at}]
      when expires_at > now ->
        {:reply, {:ok, validated_bindings, {instance_id, session_id, user_id}}, state}

      # Expiry is enforced here, not just by the periodic sweep, so a stale
      # entry can never be redeemed in the window before the next sweep pass.
      # handshake_ids are unique UUIDv4s, so a fresh insert for an expired id
      # is impossible - reject immediately rather than waiting on gossip.
      [{^handshake_id, _validated_bindings, _instance_id, _session_id, _user_id, _expires_at}] ->
        :ets.delete(@table_name, handshake_id)
        {:reply, :error, state}

      [] ->
        ref = make_ref()
        Process.send_after(self(), {:redeem_timeout, handshake_id, ref}, timeout)

        waiters =
          Map.update(state.waiters, handshake_id, [{from, ref}], &[{from, ref} | &1])

        {:noreply, %{state | waiters: waiters}}
    end
  end

  @impl GenServer
  def handle_call(:sweep_expired, _from, state) do
    delete_expired()

    {:reply, :ok, state}
  end

  # Boot-sync runs here rather than in init/1 so the blocking wait for peer
  # replies doesn't stall the supervision tree (and thus app/endpoint
  # readiness) for the full timeout on every boot. The ETS table and gossip
  # subscription are established in init/1, so direct readers and live gossip
  # are unaffected during this catch-up window.
  @impl GenServer
  def handle_continue({:boot_sync, boot_sync_timeout_ms}, state) do
    Gossip.boot_sync(@gossip_topic, boot_sync_timeout_ms, &merge_synced_entries/1)

    {:noreply, state}
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

    new_state =
      notify_waiters(state, handshake_id, validated_bindings, {instance_id, session_id, user_id})

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:redeem_timeout, handshake_id, ref}, state) do
    case Map.get(state.waiters, handshake_id) do
      nil ->
        {:noreply, state}

      waiter_list ->
        {matching, remaining} =
          Enum.split_with(waiter_list, fn {_from, waiter_ref} -> waiter_ref == ref end)

        Enum.each(matching, fn {from, _waiter_ref} -> GenServer.reply(from, :error) end)

        new_waiters =
          case remaining do
            [] -> Map.delete(state.waiters, handshake_id)
            _remaining_waiters -> Map.put(state.waiters, handshake_id, remaining)
          end

        {:noreply, %{state | waiters: new_waiters}}
    end
  end

  @impl GenServer
  def handle_info(:sweep_expired, state) do
    delete_expired()
    schedule_sweep()

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:sync_request, requester_pid}, state) do
    Gossip.reply_to_sync_request(@table_name, requester_pid)

    {:noreply, state}
  end

  defp delete_expired do
    now = System.system_time(:millisecond)

    match_spec = [
      {{:_, :_, :_, :_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ]

    :ets.select_delete(@table_name, match_spec)
  end

  defp merge_synced_entries(entries) do
    :ets.insert(@table_name, entries)
  end

  defp notify_waiters(state, handshake_id, validated_bindings, identity) do
    case Map.pop(state.waiters, handshake_id) do
      {nil, _no_waiters} ->
        state

      {waiter_list, remaining_waiters} ->
        reply = {:ok, validated_bindings, identity}

        Enum.each(waiter_list, fn {from, ref} ->
          Process.cancel_timer(ref)
          GenServer.reply(from, reply)
        end)

        %{state | waiters: remaining_waiters}
    end
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep_expired, @stash_ttl_ms)
  end
end
