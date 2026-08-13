defmodule Hologram.Realtime.SubscriptionRegistry do
  @moduledoc false

  use GenServer

  require Logger

  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake

  # One client round trip on a slow connection: the span between a boot-time command
  # reaching the server and the handshake it raced completing.
  @client_round_trip_ms 3_000

  # `Hologram.Realtime.SSE` redeems the handshake *before* it attaches, and that redemption
  # blocks for up to this long. A window at or below it can be consumed entirely by the
  # redeem wait, leaving no chance for the attach to land. Summing it in makes that floor
  # structural instead of something to remember.
  @redeem_wait_ms Handshake.server_wait_ms()

  # Headroom for server-side queueing. After a deploy, tabs reconnect in a herd, handshake
  # requests queue, and `redeem/2` grows likelier to burn its full wait - precisely when
  # first connects are most numerous.
  @server_queueing_ms 1_500

  # Summed rather than picked as one figure, so each term above carries its own reason.
  # Defined after its components because it depends on them.
  #
  # Only one situation truly needs this window: a tab's first connect, where a command
  # issued during page boot reaches the server before the handshake has attached. That
  # stream goes on to connect *successfully*, so nothing errors, the client's reconnect
  # backoff never runs, and no retry replays the receipt. Undershooting there leaves the
  # subscription unapplied until something unrelated breaks the stream or the user reloads,
  # which for a short-lived tab may be never.
  #
  # Do NOT size this against the client's reconnect cadence (`MAX_RECONNECT_DELAY` and its
  # backoff in sse.mjs). When a stream genuinely errors the client *is* retrying, and the
  # receipt signed on the timeout path replays at the next handshake and attaches the
  # binding anyway. Waiting long enough to catch that retry only withholds the command's
  # response while a working recovery is already under way.
  @attach_wait_ms @client_round_trip_ms + @redeem_wait_ms + @server_queueing_ms

  @table_name :hologram_subscriptions

  @doc """
  Applies `adds` and `drops` deltas to the registry's bindings for
  `instance_id`. Called after a same-page `command/3` returns, to fold the
  command's subscription changes into the live binding set without
  disturbing bindings the command didn't touch.

  Idempotent:

    * Re-adding an already-present key is a no-op; the existing binding's
      `authorizing_user_id` is not retagged.

    * Dropping a missing key is a no-op.

  Returns `{add_keys, drop_keys}` of the actually-applied deltas, after
  idempotence filtering, so the framework knows which adds need fresh
  receipts signed and which drops to acknowledge to the client.

  Emits zero-crossing `{:sub, channel}` / `{:unsub, channel}` messages to
  the entry's `sse_pid`: a channel sees `:sub` only when it gains its first
  cid-binding, and `:unsub` only when it loses its last. Adding or dropping
  cids for an already-bound channel is silent.

  Each added binding is tagged with `authorizing_user_id` (the authenticated
  user_id at handler time, or `nil` for anonymous). The per-binding tag lets
  later identity changes selectively drop bindings whose authorization no
  longer holds.

  When no entry exists at call time the caller is parked rather than answered.
  A lookup miss has three causes with different correct responses: the
  connection is attaching right now (a command issued during page boot races the
  SSE handshake), it is live on another node of the cluster, or it is genuinely
  gone (the connection died and was garbage-collected by the registry's `:DOWN`
  handler). Answering immediately assumes the last and silently discards the
  deltas in the other two.

  So a parked caller is released by whichever of these resolves first:

    * `attach_connection/5`, which applies the deltas against the entry it has
      just created and replies with the real result. Ordering is therefore
      correct by construction: the attach establishes the handshake baseline and
      the parked deltas fold in on top of it, rather than the two racing.
      Callers parked for the same instance are released in the order they were
      issued.

    * The node that holds the connection, which is asked over the instance's
      announce topic when the caller is parked, applies the deltas against its
      own registry and answers.

  If no connection attaches within `attach_wait_ms/0`, no entry is created and
  no zero-crossing messages are emitted, and the input `adds` and `drops` are
  returned unchanged so the framework can still sign receipts and ship a
  coherent response to the client. Receipts signed on that path stay valid and
  reattach their bindings at the client's next handshake, and the unapplied
  deltas are logged as a warning so the case is visible rather than silent.
  """
  @spec apply_deltas(String.t(), [{any, String.t()}], [{any, String.t()}], term | nil) ::
          {[{any, String.t()}], [{any, String.t()}]}
  def apply_deltas(instance_id, adds, drops, authorizing_user_id) do
    message = {:apply_deltas, instance_id, adds, drops, authorizing_user_id}

    # The server bounds this call on its own: a parked caller is released either by
    # attach_connection/5 or by its own timer, so every path replies. A client-side
    # timeout would be a second bound that has to track whatever wait `start_link/1`
    # was given, and would cut the caller off early whenever the two drift.
    # `GenServer.call/3` monitors the server regardless, so a dead registry still
    # exits the caller immediately rather than hanging it.
    GenServer.call(__MODULE__, message, :infinity)
  end

  @doc """
  Attaches a fresh SSE connection to `instance_id`. The handshake endpoint
  owns all signature / identity / tombstone verification ahead of this
  call - `attach_connection/5` itself trusts the supplied bindings.

  `validated_bindings` is a list of `{{channel, cid}, authorizing_user_id}`
  pairs (map-compatible). The function monitors `sse_pid` so the entry is
  cleaned up when the connection dies, and returns the deduped list of
  channels in the resulting binding set so the caller can subscribe the SSE
  process to PubSub topics.

  Two paths:

    * **No prior entry** (initial attach, or reconnect after the prior entry
      was garbage-collected): create a fresh entry whose `bindings` field
      equals exactly the supplied `validated_bindings`.

    * **Prior entry exists** (newest-attach-wins): demonitor the prior
      `sse_pid`, send it `{:close, :superseded}` for graceful shutdown, and
      swap the entry to the new pid + monitor. The prior canonical binding
      set (including each binding's `authorizing_user_id`) is preserved so
      PubSub subs don't churn through zero-crossings during the swap; the
      new client's `validated_bindings` is intentionally ignored in this
      path because the live registry's state is the source of truth.
  """
  @spec attach_connection(String.t(), term | nil, term | nil, pid, [
          {{any, String.t()}, term | nil}
        ]) ::
          [any]
  def attach_connection(instance_id, session_id, user_id, sse_pid, validated_bindings) do
    GenServer.call(
      __MODULE__,
      {:attach_connection, instance_id, session_id, user_id, sse_pid, validated_bindings}
    )
  end

  @doc """
  Returns how long `apply_deltas/4` waits for a connection to attach before
  giving up and returning its deltas unapplied. A parked caller is released as
  soon as one attaches, so the full window is only ever paid when none arrives.
  """
  @spec attach_wait_ms() :: pos_integer
  def attach_wait_ms, do: @attach_wait_ms

  @doc """
  Returns the `bindings` map (`%{ {channel, cid} => authorizing_user_id | nil }`)
  for the given `instance_id`, or `nil` if no entry exists. Reads ETS directly
  to bypass the registry's GenServer mailbox.
  """
  @spec bindings_of(String.t()) :: %{{any, String.t()} => term | nil} | nil
  def bindings_of(instance_id) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] -> entry.bindings
      [] -> nil
    end
  end

  @doc """
  Drops every binding from the entry for `instance_id` whose
  `authorizing_user_id` is non-nil and does not equal `new_user_id`.
  Anonymous-authorized bindings (`authorizing_user_id == nil`) stay live -
  the elevation rule means they apply equally to any subsequent identity.

  Returns `{dropped_keys, zero_crossing_channels}`:

    * `dropped_keys` is the list of `{channel, cid}` pairs that were removed.

    * `zero_crossing_channels` is the list of channels whose last cid-binding
      was dropped (i.e., the channel is no longer present in the resulting
      binding set). Channels that still have surviving cid-bindings under
      anonymous or matching-user authorization are not included.

  When no entry exists for `instance_id`, returns `{[], []}`.
  """
  @spec drop_for_identity_change(String.t(), term | nil) ::
          {[{any, String.t()}], [any]}
  def drop_for_identity_change(instance_id, new_user_id) do
    GenServer.call(__MODULE__, {:drop_for_identity_change, instance_id, new_user_id})
  end

  @doc """
  Drops the given `keys` from the entry's `bindings` for `instance_id`.

  Returns `{actually_dropped, zero_crossing_channels}`:

    * `actually_dropped` is the subset of `keys` that were present in the
      bindings before the call.

    * `zero_crossing_channels` is the list of channels whose last cid-binding
      was dropped.

  Unlike `apply_deltas/4`, this function does *not* emit `{:unsub, channel}`
  self-messages to the SSE process - the caller drives synchronous PubSub
  unsubscribe based on the returned `zero_crossing_channels` to control
  ordering against downstream notifications.

  When no entry exists for `instance_id`, returns `{[], []}`.
  """
  @spec drop_keys(String.t(), [{any, String.t()}]) ::
          {[{any, String.t()}], [any]}
  def drop_keys(instance_id, keys) do
    GenServer.call(__MODULE__, {:drop_keys, instance_id, keys})
  end

  @doc """
  Returns the name of the ETS table that backs the registry.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns `{session_id, user_id}` for the given `instance_id`, or `nil` if no
  entry exists. Reads ETS directly to bypass the registry's GenServer mailbox.
  """
  @spec identity_of(String.t()) :: {term | nil, term | nil} | nil
  def identity_of(instance_id) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] -> {entry.session_id, entry.user_id}
      [] -> nil
    end
  end

  @doc """
  Registers an SSE connection for the given `instance_id` by inserting an entry
  into the ETS table. The registry monitors `sse_pid` so the entry can be
  cleaned up when the pid goes down.

  Inserted entry shape per `instance_id`:

      %{
        bindings:   %{ {channel, cid} => authorizing_user_id | nil },
        session_id: term | nil,
        sse_pid:    pid,
        sse_ref:    reference,
        user_id:    term | nil
      }

  `bindings` is initialized to `%{}` and populated later via `transition/4` /
  `apply_deltas/4`. `session_id` and `user_id` are initialized to `nil` and
  populated later via the identity-update helpers.
  """
  @spec register_connection(String.t(), pid) :: :ok
  def register_connection(instance_id, sse_pid) do
    GenServer.call(__MODULE__, {:register_connection, instance_id, sse_pid})
  end

  @doc """
  Resolves an identity tuple to the list of live `{instance_id, sse_pid}`
  entries whose registry record matches.

  Accepted identity shapes:

    * `{:instance, instance_id}` - returns the matching entry (single-element
      list) or an empty list.

    * `{:session, session_id}` - returns every entry whose `session_id` equals
      the given value.

    * `{:user, user_id}` - returns every entry whose `user_id` equals the
      given value.

  Reads ETS directly. The returned `sse_pid` values may already be down between
  the lookup and the caller's subsequent `send/2`; the registry cleans up dead
  pids asynchronously via its `:DOWN` handler.
  """
  @spec resolve_identity({:instance, String.t()} | {:session, term} | {:user, term}) ::
          [{String.t(), pid}]
  def resolve_identity({:instance, instance_id}) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] -> [{instance_id, entry.sse_pid}]
      [] -> []
    end
  end

  def resolve_identity({:session, session_id}) do
    resolve_by_field(:session_id, session_id)
  end

  def resolve_identity({:user, user_id}) do
    resolve_by_field(:user_id, user_id)
  end

  @doc """
  Starts the subscription registry process.

  ## Options

    * `:attach_wait_ms` - overrides how long `apply_deltas/4` parks a caller
      whose instance has no entry yet. Defaults to `attach_wait_ms/0`.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Transitions the registry's binding set for `instance_id` to the bindings
  derived from `new_sub_keys`. Called after a page render's `init/3` returns
  to reconcile the new page's subscription set against both the client's
  previously-known bindings and the registry's prior bindings.

  Computes two parallel set-differences:

    * **Client-side diff** against `client_claimed_sub_keys` - returned as
      `{add_keys, drop_keys}` so the caller can hand the client an
      `{adds, drops}` payload to update its local subscription tracking.

    * **PubSub-side diff** against the registry's prior `bindings` - drives
      zero-crossing `{:sub, channel}` / `{:unsub, channel}` messages sent to
      the entry's `sse_pid`. A channel only sees `:sub` on its first
      cid-binding, and only sees `:unsub` when its last cid-binding is
      dropped; adding or removing intermediate cids for an already-bound
      channel is silent.

  When an entry exists, the `bindings` field is replaced wholesale (page
  navigation defines the complete set, not deltas), and each new binding is
  tagged with `authorizing_user_id` (the authenticated user_id at handler
  time, or `nil` for anonymous). The per-binding tag lets later identity
  changes selectively drop bindings whose authorization no longer holds.

  When no entry exists at call time (the SSE connection has already died and
  been garbage-collected by the registry's `:DOWN` handler), the call is
  alive-only: no entry is created and no zero-crossing messages are emitted,
  but the client-side diff is still returned so the caller can respond
  coherently.
  """
  @spec transition(String.t(), [{any, String.t()}], [{any, String.t()}], term | nil) ::
          {[{any, String.t()}], [{any, String.t()}]}
  def transition(instance_id, new_sub_keys, client_claimed_sub_keys, authorizing_user_id) do
    GenServer.call(
      __MODULE__,
      {:transition, instance_id, new_sub_keys, client_claimed_sub_keys, authorizing_user_id}
    )
  end

  @doc """
  Updates the `session_id` and `user_id` fields of the entry for the given
  `instance_id`. No-op when no entry exists.
  """
  @spec update_identity(String.t(), term | nil, term | nil) :: :ok
  def update_identity(instance_id, session_id, user_id) do
    GenServer.call(__MODULE__, {:update_identity, instance_id, session_id, user_id})
  end

  @impl GenServer
  def init(opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    attach_wait_ms = Keyword.get(opts, :attach_wait_ms, @attach_wait_ms)

    # `refs` maps each monitor reference to its instance_id, so a :DOWN can find
    # the entry to delete. `waiters` holds callers parked because their instance
    # has no entry yet, keyed by instance_id.
    {:ok, %{attach_wait_ms: attach_wait_ms, refs: %{}, waiters: %{}}}
  end

  @impl GenServer
  def handle_call({:apply_deltas, instance_id, adds, drops, authorizing_user_id}, from, state) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] ->
        reply = apply_deltas_to_entry(instance_id, entry, adds, drops, authorizing_user_id)

        {:reply, reply, state}

      # The connection may be attaching right now, live on another node, or gone. Park
      # the caller and ask the cluster in the same breath - whichever resolves first
      # releases it.
      [] ->
        {new_state, waiter_ref} =
          park_caller(state, instance_id, from, adds, drops, authorizing_user_id)

        topic = Realtime.instance_announce_topic(instance_id)

        message =
          {:apply_deltas_remote, instance_id, adds, drops, authorizing_user_id, self(),
           waiter_ref}

        Phoenix.PubSub.broadcast(Hologram.PubSub, topic, message)

        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_call(
        {:attach_connection, instance_id, session_id, user_id, sse_pid, validated_bindings},
        _from,
        state
      ) do
    {bindings, refs_without_prior} =
      case :ets.lookup(@table_name, instance_id) do
        [] ->
          {Map.new(validated_bindings), state.refs}

        [{^instance_id, %{sse_pid: prior_pid, sse_ref: prior_ref, bindings: prior_bindings}}] ->
          Process.demonitor(prior_ref, [:flush])
          send(prior_pid, {:close, :superseded})
          {prior_bindings, Map.delete(state.refs, prior_ref)}
      end

    sse_ref = Process.monitor(sse_pid)

    entry = %{
      bindings: bindings,
      session_id: session_id,
      sse_pid: sse_pid,
      sse_ref: sse_ref,
      user_id: user_id
    }

    :ets.insert(@table_name, {instance_id, entry})

    validated_channels =
      bindings
      |> channels_of()
      |> MapSet.to_list()

    new_refs = Map.put(refs_without_prior, sse_ref, instance_id)

    # Drained after the insert so the parked deltas fold into the entry this attach
    # just established. Channels they newly bind reach the SSE process as ordinary
    # zero-crossing messages, so they need no place in validated_channels.
    new_waiters = drain_waiters(state.waiters, instance_id)

    {:reply, validated_channels, %{state | refs: new_refs, waiters: new_waiters}}
  end

  @impl GenServer
  def handle_call({:drop_for_identity_change, instance_id, new_user_id}, _from, state) do
    reply =
      case :ets.lookup(@table_name, instance_id) do
        [{^instance_id, entry}] ->
          prior_bindings = entry.bindings

          dropped_keys =
            prior_bindings
            |> Enum.filter(fn {_key, authorizing_user_id} ->
              authorizing_user_id != nil and authorizing_user_id != new_user_id
            end)
            |> Enum.map(fn {key, _user_id} -> key end)

          new_bindings = Map.drop(prior_bindings, dropped_keys)

          :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings}})

          prior_channels = channels_of(prior_bindings)
          new_channels = channels_of(new_bindings)

          {dropped_keys, unsub_channels(prior_channels, new_channels)}

        [] ->
          {[], []}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:drop_keys, instance_id, keys}, _from, state) do
    reply =
      case :ets.lookup(@table_name, instance_id) do
        [{^instance_id, entry}] ->
          prior_bindings = entry.bindings

          actually_dropped = Enum.filter(keys, &Map.has_key?(prior_bindings, &1))
          new_bindings = Map.drop(prior_bindings, actually_dropped)

          :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings}})

          prior_channels = channels_of(prior_bindings)
          new_channels = channels_of(new_bindings)

          {actually_dropped, unsub_channels(prior_channels, new_channels)}

        [] ->
          {[], []}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:register_connection, instance_id, sse_pid}, _from, state) do
    sse_ref = Process.monitor(sse_pid)

    entry = %{
      bindings: %{},
      session_id: nil,
      sse_pid: sse_pid,
      sse_ref: sse_ref,
      user_id: nil
    }

    :ets.insert(@table_name, {instance_id, entry})

    new_refs = Map.put(state.refs, sse_ref, instance_id)

    {:reply, :ok, %{state | refs: new_refs}}
  end

  @impl GenServer
  def handle_call(
        {:transition, instance_id, new_sub_keys, client_claimed_sub_keys, authorizing_user_id},
        _from,
        state
      ) do
    new_keys_set = MapSet.new(new_sub_keys)
    client_keys_set = MapSet.new(client_claimed_sub_keys)

    add_keys =
      new_keys_set
      |> MapSet.difference(client_keys_set)
      |> MapSet.to_list()

    drop_keys =
      client_keys_set
      |> MapSet.difference(new_keys_set)
      |> MapSet.to_list()

    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] ->
        new_bindings_map = Map.new(new_sub_keys, fn key -> {key, authorizing_user_id} end)
        :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings_map}})

        prior_channels = channels_of(entry.bindings)
        new_channels = channels_of(new_bindings_map)

        emit_zero_crossings(entry.sse_pid, prior_channels, new_channels)

      [] ->
        :noop
    end

    {:reply, {add_keys, drop_keys}, state}
  end

  @impl GenServer
  def handle_call({:update_identity, instance_id, session_id, user_id}, _from, state) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] ->
        new_entry = %{entry | session_id: session_id, user_id: user_id}
        :ets.insert(@table_name, {instance_id, new_entry})

      [] ->
        :noop
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:apply_deltas_timeout, instance_id, timer_ref}, state) do
    case Map.get(state.waiters, instance_id) do
      nil ->
        {:noreply, state}

      waiter_list ->
        {matching, remaining} =
          Enum.split_with(waiter_list, fn {_from, ref, _adds, _drops, _user_id} ->
            ref == timer_ref
          end)

        Enum.each(matching, fn {from, _ref, adds, drops, _user_id} ->
          log_unapplied_deltas(instance_id, adds, drops, state.attach_wait_ms)
          GenServer.reply(from, {adds, drops})
        end)

        new_waiters =
          case remaining do
            [] -> Map.delete(state.waiters, instance_id)
            _remaining_waiters -> Map.put(state.waiters, instance_id, remaining)
          end

        {:noreply, %{state | waiters: new_waiters}}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {instance_id, new_refs} ->
        :ets.delete(@table_name, instance_id)
        {:noreply, %{state | refs: new_refs}}
    end
  end

  defp apply_deltas_to_entry(instance_id, entry, adds, drops, authorizing_user_id) do
    prior_bindings = entry.bindings

    actually_added = Enum.reject(adds, &Map.has_key?(prior_bindings, &1))
    actually_dropped = Enum.filter(drops, &Map.has_key?(prior_bindings, &1))

    new_bindings =
      prior_bindings
      |> Map.drop(actually_dropped)
      |> Map.merge(Map.new(actually_added, fn key -> {key, authorizing_user_id} end))

    :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings}})

    prior_channels = channels_of(prior_bindings)
    new_channels = channels_of(new_bindings)

    emit_zero_crossings(entry.sse_pid, prior_channels, new_channels)

    {actually_added, actually_dropped}
  end

  defp channels_of(bindings) do
    MapSet.new(bindings, fn {{channel, _cid}, _user_id} -> channel end)
  end

  defp drain_waiters(waiters, instance_id) do
    {waiter_list, remaining_waiters} = Map.pop(waiters, instance_id, [])

    waiter_list
    |> Enum.reverse()
    |> Enum.each(fn {from, _timer_ref, adds, drops, authorizing_user_id} ->
      # Re-read per waiter so each set of deltas folds into the result of the last.
      [{^instance_id, entry}] = :ets.lookup(@table_name, instance_id)
      reply = apply_deltas_to_entry(instance_id, entry, adds, drops, authorizing_user_id)

      GenServer.reply(from, reply)
    end)

    remaining_waiters
  end

  defp emit_zero_crossings(sse_pid, prior_channels, new_channels) do
    new_channels
    |> MapSet.difference(prior_channels)
    |> Enum.each(fn channel -> send(sse_pid, {:sub, channel}) end)

    prior_channels
    |> MapSet.difference(new_channels)
    |> Enum.each(fn channel -> send(sse_pid, {:unsub, channel}) end)
  end

  defp log_unapplied_deltas(instance_id, adds, drops, wait_ms) do
    message = """
    No connection attached for instance #{inspect(instance_id)} within #{wait_ms}ms, \
    so its subscription deltas were not applied \
    (adds: #{inspect(adds)}, drops: #{inspect(drops)}). \
    Receipts already issued for these bindings stay valid and reattach the subscriptions \
    at the client's next handshake.\
    """

    Logger.warning(message)
  end

  defp park_caller(state, instance_id, from, adds, drops, authorizing_user_id) do
    timer_ref = make_ref()
    timeout_message = {:apply_deltas_timeout, instance_id, timer_ref}

    Process.send_after(self(), timeout_message, state.attach_wait_ms)

    # The timer is left to fire even when the waiter is released early. Its handler
    # matches on timer_ref, finds nothing, and returns - cheaper than tracking a
    # second reference solely to cancel it.
    waiter = {from, timer_ref, adds, drops, authorizing_user_id}

    # Prepended for O(1) insert. The drain reverses, so deltas parked for the same
    # instance apply in the order they were issued.
    waiters = Map.update(state.waiters, instance_id, [waiter], &[waiter | &1])

    # The ref goes back to the caller so it can be sent to the connection's holder as a
    # correlation id, letting a reply address exactly this waiter.
    {%{state | waiters: waiters}, timer_ref}
  end

  defp resolve_by_field(field, value) do
    @table_name
    |> :ets.tab2list()
    |> Enum.filter(fn {_instance_id, entry} -> Map.get(entry, field) == value end)
    |> Enum.map(fn {instance_id, entry} -> {instance_id, entry.sse_pid} end)
  end

  defp unsub_channels(prior_channels, new_channels) do
    prior_channels
    |> MapSet.difference(new_channels)
    |> Enum.to_list()
  end
end
