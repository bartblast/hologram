defmodule Hologram.Realtime.SubscriptionRegistry do
  @moduledoc false

  use GenServer

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

  When no entry exists at call time (the SSE connection has already died and
  been garbage-collected by the registry's `:DOWN` handler), the call is
  alive-only: no entry is created and no zero-crossing messages are emitted.
  The input `adds` and `drops` are returned unchanged so the framework can
  still sign receipts and ship a coherent response to the client.
  """
  @spec apply_deltas(String.t(), [{any, String.t()}], [{any, String.t()}], term | nil) ::
          {[{any, String.t()}], [{any, String.t()}]}
  def apply_deltas(instance_id, adds, drops, authorizing_user_id) do
    GenServer.call(__MODULE__, {:apply_deltas, instance_id, adds, drops, authorizing_user_id})
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
  @spec register(String.t(), pid) :: :ok
  def register(instance_id, sse_pid) do
    GenServer.call(__MODULE__, {:register, instance_id, sse_pid})
  end

  @doc """
  Starts the subscription registry process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Transitions the registry's binding set for `instance_id` to `new_bindings`.
  Called after a page render's `init/3` returns to reconcile the new page's
  subscription set against both the client's previously-known bindings and the
  registry's prior bindings.

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
  def transition(instance_id, new_bindings, client_claimed_sub_keys, authorizing_user_id) do
    GenServer.call(
      __MODULE__,
      {:transition, instance_id, new_bindings, client_claimed_sub_keys, authorizing_user_id}
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
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:apply_deltas, instance_id, adds, drops, authorizing_user_id}, _from, refs) do
    reply =
      case :ets.lookup(@table_name, instance_id) do
        [{^instance_id, entry}] ->
          prior_bindings = entry.bindings

          actually_added = Enum.reject(adds, &Map.has_key?(prior_bindings, &1))
          actually_dropped = Enum.filter(drops, &Map.has_key?(prior_bindings, &1))

          new_bindings =
            prior_bindings
            |> Map.drop(actually_dropped)
            |> Map.merge(Map.new(actually_added, fn key -> {key, authorizing_user_id} end))

          :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings}})

          prior_channels =
            MapSet.new(prior_bindings, fn {{channel, _cid}, _user_id} -> channel end)

          new_channels = MapSet.new(new_bindings, fn {{channel, _cid}, _user_id} -> channel end)

          new_channels
          |> MapSet.difference(prior_channels)
          |> Enum.each(fn channel -> send(entry.sse_pid, {:sub, channel}) end)

          prior_channels
          |> MapSet.difference(new_channels)
          |> Enum.each(fn channel -> send(entry.sse_pid, {:unsub, channel}) end)

          {actually_added, actually_dropped}

        [] ->
          {adds, drops}
      end

    {:reply, reply, refs}
  end

  @impl GenServer
  def handle_call(
        {:attach_connection, instance_id, session_id, user_id, sse_pid, validated_bindings},
        _from,
        refs
      ) do
    {bindings, refs_without_prior} =
      case :ets.lookup(@table_name, instance_id) do
        [] ->
          {Map.new(validated_bindings), refs}

        [{^instance_id, %{sse_pid: prior_pid, sse_ref: prior_ref, bindings: prior_bindings}}] ->
          Process.demonitor(prior_ref, [:flush])
          send(prior_pid, {:close, :superseded})
          {prior_bindings, Map.delete(refs, prior_ref)}
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
      |> Enum.map(fn {{channel, _cid}, _user_id} -> channel end)
      |> Enum.uniq()

    {:reply, validated_channels, Map.put(refs_without_prior, sse_ref, instance_id)}
  end

  @impl GenServer
  def handle_call({:register, instance_id, sse_pid}, _from, refs) do
    sse_ref = Process.monitor(sse_pid)

    entry = %{
      bindings: %{},
      session_id: nil,
      sse_pid: sse_pid,
      sse_ref: sse_ref,
      user_id: nil
    }

    :ets.insert(@table_name, {instance_id, entry})

    {:reply, :ok, Map.put(refs, sse_ref, instance_id)}
  end

  @impl GenServer
  def handle_call(
        {:transition, instance_id, new_bindings, client_claimed_sub_keys, authorizing_user_id},
        _from,
        refs
      ) do
    new_keys_set = MapSet.new(new_bindings)
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
        new_bindings_map = Map.new(new_bindings, fn key -> {key, authorizing_user_id} end)
        :ets.insert(@table_name, {instance_id, %{entry | bindings: new_bindings_map}})

        prior_channels =
          MapSet.new(entry.bindings, fn {{channel, _cid}, _user_id} -> channel end)

        new_channels = MapSet.new(new_bindings, fn {channel, _cid} -> channel end)

        new_channels
        |> MapSet.difference(prior_channels)
        |> Enum.each(fn channel -> send(entry.sse_pid, {:sub, channel}) end)

        prior_channels
        |> MapSet.difference(new_channels)
        |> Enum.each(fn channel -> send(entry.sse_pid, {:unsub, channel}) end)

      [] ->
        :noop
    end

    {:reply, {add_keys, drop_keys}, refs}
  end

  @impl GenServer
  def handle_call({:update_identity, instance_id, session_id, user_id}, _from, refs) do
    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, entry}] ->
        new_entry = %{entry | session_id: session_id, user_id: user_id}
        :ets.insert(@table_name, {instance_id, new_entry})

      [] ->
        :noop
    end

    {:reply, :ok, refs}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, refs) do
    case Map.pop(refs, ref) do
      {nil, refs} ->
        {:noreply, refs}

      {instance_id, new_refs} ->
        :ets.delete(@table_name, instance_id)
        {:noreply, new_refs}
    end
  end
end
