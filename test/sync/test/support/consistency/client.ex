defmodule HologramSyncTests.Consistency.Client do
  @moduledoc false

  # A simulated browser tab: a process holding a sync stream and a store it keeps the way the
  # browser keeps its local database, so the consistency checks can compare what it holds with
  # what its user may read. It mirrors `assets/js/deltas.mjs`, the frame handling of
  # `assets/js/sync_stream.mjs` and the refill and sweep of `assets/js/local_database.mjs`, and
  # nothing else of the browser: it renders nothing, writes nothing and holds no tab group.
  #
  # The stream is `Hologram.Test.SyncClient`'s, started from this process so its messages arrive
  # here, and read as they come rather than waited on - a frame changes the store the moment it
  # arrives, the way it does in a browser.

  # Temporary: a client that crashed is a failure to see, not one to restart empty.
  use GenServer, restart: :temporary

  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Frame
  alias Hologram.Test.SyncClient
  alias HologramSyncTests.Consistency.Model

  @page "HologramSyncTests.ConsistencyPage"

  # What the browser waits before reconnecting a stream that ended (`assets/js/sse.mjs`).
  @reconnect_delay_ms 250

  @typedoc """
  A put or a patch of one of the model's rows, as the client received it: the monotonic time read
  before the connect that carried it started, the time the chunk completing its frame arrived, the
  transaction id bounding it, the declared fields it carried, and whether the client applied it - a
  patch for a row it doesn't hold is passed over, and is a row the server sent all the same.

  The bound is the frame's cursor, or, for a frame carrying none, the place the client held when it
  arrived: only a batch's last frame carries one, and the server read the batch's rows after every
  transaction below the client's place had ended - a client cut off right there comes back from
  it. Nil when the client held no place either.
  """
  @type received :: %{
          applied?: boolean,
          carried: map,
          cursor_tx: non_neg_integer | nil,
          id: String.t(),
          opened_at: integer,
          received_at: integer,
          type: module
        }

  @doc """
  Starts a client of the given `:user_id` (nil for an anonymous session) against `:base_url`,
  holding nothing and not connected.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Returns whether the client's stream has told it, since it last connected, that it holds
  everything.
  """
  @spec complete?(pid) :: boolean
  def complete?(client), do: GenServer.call(client, :complete?)

  @doc """
  Opens the client's stream, coming back from its cursor when it has one. Without one it begins a
  refill first, the way a browser greeting with no place does, so the marker ending the fill sweeps
  whatever the server no longer sends. Does nothing when the stream is already open.

  `:cut_when` is a function given the client's events, newest first, after each frame this
  connection carries: the first time it answers true the client cuts the stream there, passing
  over the rest of the chunk the way a connection dropping would - for a cut at one point of a fill
  or a catch-up. It goes with the connection, so one that never fires doesn't carry over to the
  next, and a connect finding the stream open takes it back.
  """
  @spec connect(pid, keyword) :: :ok
  def connect(client, opts \\ []), do: GenServer.call(client, {:connect, opts}, 30_000)

  @doc """
  Returns the place the client would come back from, or nil.
  """
  @spec cursor(pid) :: String.t() | nil
  def cursor(client), do: GenServer.call(client, :cursor)

  @doc """
  Closes the client's stream, the way a tab losing its connection does, and keeps it closed until
  `connect/1`. The store and the cursor stay.
  """
  @spec cut(pid) :: :ok
  def cut(client), do: GenServer.call(client, :cut)

  @doc """
  Returns what the client recorded, oldest first, each with its `:kind`: a `:connect`, a `:closed`
  stream (its `:cause` a cut, a stream end or an error), a `:frame` summary (its `:frame` the SSE
  event kind), and a `:failure` (its `:failure` naming it) - a frame no browser of this build should
  get, an op the browser doesn't know, a refused connection, or a cursor this client can't read.
  """
  @spec events(pid) :: list(map)
  def events(client), do: GenServer.call(client, :events)

  @doc """
  Puts the given place in the client, as one it would come back from - for a test of a client
  holding a place the server can't read, the way a tab of another build can.
  """
  @spec put_cursor(pid, String.t() | nil) :: :ok
  def put_cursor(client, cursor), do: GenServer.call(client, {:put_cursor, cursor})

  @doc """
  Returns the failures among the client's events.
  """
  @spec failures(pid) :: list(map)
  def failures(client) do
    client
    |> events()
    |> Enum.filter(&(&1.kind == :failure))
  end

  @doc """
  Returns every put and patch of the model's rows the client received, oldest first.
  """
  @spec records(pid) :: list(received)
  def records(client), do: GenServer.call(client, :records)

  @doc """
  Stops the client, closing its stream, waiting at most the given milliseconds.
  """
  @spec stop(pid, timeout) :: :ok
  def stop(client, timeout \\ :infinity), do: GenServer.stop(client, :normal, timeout)

  @doc """
  Returns what the client holds of the model's types, in the shape `Model.expected/2` answers: the
  rows of each type by id, with their declared fields and their sets as sorted ids.
  """
  @spec store(pid) :: %{module => %{String.t() => map}}
  def store(client), do: GenServer.call(client, :store)

  @doc """
  Returns whether the client's stream has told it, since it last connected, that it holds
  everything, and what it holds (see `store/1`) - read in one go, so both describe one moment.
  """
  @spec view(pid) :: {boolean, %{module => %{String.t() => map}}}
  def view(client), do: GenServer.call(client, :view)

  @impl GenServer
  def init(opts) do
    # So a supervisor stopping it runs terminate/2, which closes the stream: :httpc keeps a stream
    # open after the process that asked for it is gone, and the server would go on serving it.
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       awaiting: MapSet.new(),
       base_url: Keyword.fetch!(opts, :base_url),
       buffer: "",
       complete?: false,
       cursor: nil,
       cut_when: nil,
       events: [],
       facts: %{},
       opened_at: nil,
       reconnect: nil,
       records: [],
       stream: nil,
       synced_all: false,
       synced_types: MapSet.new(),
       tables: %{},
       user_id: Keyword.get(opts, :user_id)
     }}
  end

  @impl GenServer
  def handle_call(:complete?, _from, state), do: {:reply, state.complete?, state}

  def handle_call({:connect, opts}, _from, %{stream: nil} = state) do
    {:reply, :ok, open(%{state | cut_when: Keyword.get(opts, :cut_when)})}
  end

  # Already connected: a cut armed for the connection that never fired goes, so it can't cut the
  # stream later, when nothing is left to reconnect it.
  def handle_call({:connect, _opts}, _from, state), do: {:reply, :ok, %{state | cut_when: nil}}

  def handle_call(:cursor, _from, state), do: {:reply, state.cursor, state}

  def handle_call(:cut, _from, state),
    do: {:reply, :ok, cancel_reconnect(close(state, :cut))}

  def handle_call({:put_cursor, cursor}, _from, state),
    do: {:reply, :ok, %{state | cursor: cursor}}

  def handle_call(:events, _from, state), do: {:reply, Enum.reverse(state.events), state}

  def handle_call(:records, _from, state), do: {:reply, Enum.reverse(state.records), state}

  def handle_call(:store, _from, state), do: {:reply, comparable_store(state), state}

  def handle_call(:view, _from, state) do
    {:reply, {state.complete?, comparable_store(state)}, state}
  end

  @impl GenServer
  # Only the reconnect the client still waits for: a cut or a connect since then took it back, even
  # when its message was already on the way.
  def handle_info({:reconnect, ref}, %{reconnect: ref} = state) do
    {:noreply, open(%{state | reconnect: nil})}
  end

  def handle_info({:reconnect, _ref}, state), do: {:noreply, state}

  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  def handle_info(
        {:http, {request_id, kind, payload}},
        %{stream: %{request_id: request_id}} = state
      ) do
    {:noreply, handle_stream({kind, payload}, state)}
  end

  def handle_info({:http, {request_id, result}}, %{stream: %{request_id: request_id}} = state) do
    {:noreply, handle_stream(result, state)}
  end

  # A message of a request the client no longer reads - a stream it cut, whose chunks were already
  # on their way. Applying them would write old frames over what came since.
  def handle_info({:http, _message}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    if state.stream, do: SyncClient.close(state.stream)

    :ok
  end

  defp handle_stream({:stream_start, _headers}, state), do: state

  defp handle_stream({:stream, chunk}, state) do
    received_at = System.monotonic_time()
    {frames, rest} = SyncClient.parse_frames(state.buffer <> chunk)

    Enum.reduce_while(frames, %{state | buffer: rest}, fn frame, acc ->
      handled = handle_frame(frame, acc, received_at)

      if cut_now?(handled) do
        {:halt, close(handled, :cut)}
      else
        {:cont, handled}
      end
    end)
  end

  defp handle_stream({:stream_end, _headers}, state), do: ended(state, :stream_end)

  defp handle_stream({:error, reason}, state), do: ended(state, {:error, reason})

  # A response that isn't a stream - the server refusing the connection outright, which it never
  # should a client of this build.
  defp handle_stream({status_line, _headers, body}, state) do
    state
    |> event(:failure, %{failure: "refused", body: body, status: status_line})
    |> ended({:refused, status_line})
  end

  defp cut_now?(%{cut_when: nil}), do: false

  defp cut_now?(state), do: state.cut_when.(state.events)

  defp ended(state, reason) do
    ref = make_ref()
    Process.send_after(self(), {:reconnect, ref}, @reconnect_delay_ms)

    %{close(state, reason) | reconnect: ref}
  end

  defp cancel_reconnect(state), do: %{state | reconnect: nil}

  defp open(%{stream: nil} = state) do
    opened_at = System.monotonic_time()
    resuming? = state.cursor != nil
    refilling = if resuming?, do: state, else: begin_refill(state)

    stream =
      SyncClient.connect(state.base_url,
        cookie_path: cookie_path(state.user_id),
        cursor: state.cursor,
        page: @page
      )

    refilling
    |> Map.merge(%{
      buffer: "",
      complete?: false,
      opened_at: opened_at,
      reconnect: nil,
      stream: stream
    })
    |> event(:connect, %{cursor: state.cursor, request_id: stream.request_id})
  end

  defp open(state), do: state

  defp close(%{stream: nil} = state, _reason), do: state

  defp close(state, reason) do
    SyncClient.close(state.stream)

    closed = %{state | buffer: "", complete?: false, cut_when: nil, stream: nil}

    event(closed, :closed, %{cause: reason})
  end

  defp cookie_path(nil), do: "/plain"

  defp cookie_path(user_id), do: "/consistency/#{user_id}"

  defp handle_frame(%{"event" => "sync_deltas", "data" => data}, state, received_at) do
    frame = Jason.decode!(data, objects: :ordered_objects)
    cursor = field(frame, "cursor")
    bound = cursor || state.cursor

    applied =
      frame
      |> field("deltas")
      |> pairs()
      |> Enum.reduce(state, fn {op, by_type}, acc ->
        by_type
        |> pairs()
        |> Enum.reduce(acc, fn {type, items}, type_acc ->
          apply_group(type_acc, op, type, plain(items), {bound, received_at})
        end)
      end)

    applied
    |> keep_cursor(cursor)
    |> event(:frame, %{cursor: cursor, frame: "sync_deltas", ops: ops_summary(frame)})
  end

  defp handle_frame(%{"event" => "synced", "data" => data}, state, _received_at) do
    frame = Jason.decode!(data)

    marked =
      case frame["scope"] do
        "all" -> %{mark_all_synced(state) | complete?: true}
        "types" -> mark_types_synced(state, frame["types"])
        _unknown_scope -> state
      end

    marked
    |> keep_cursor(frame["cursor"])
    |> event(:frame, %{cursor: frame["cursor"], frame: "synced", scope: frame["scope"]})
  end

  defp handle_frame(%{"event" => "sync_resync", "data" => data}, state, _received_at) do
    %{"reason" => reason} = Jason.decode!(data)

    refilled = if reason == "identity", do: reset(state), else: begin_refill(state)

    event(%{refilled | complete?: false, cursor: nil}, :frame, %{
      frame: "sync_resync",
      reason: reason
    })
  end

  # The model and the rules this client greets with are the server's own, so neither of these may
  # ever come.
  defp handle_frame(%{"event" => kind, "data" => data}, state, _received_at)
       when kind in ["sync_reload", "sync_rules"] do
    event(state, :failure, %{data: data, failure: kind})
  end

  defp handle_frame(_frame, state, _received_at), do: state

  # An op the browser doesn't know throws there, so it's a failure here.
  defp apply_group(state, op, type, _items, _origin)
       when op not in ~w(add_relationship del_entity del_relationship keep_hashed patch_entity
                         put_entity unsync_entity unsync_hashed) do
    event(state, :failure, %{failure: "unknown op", op: op, type: type})
  end

  defp apply_group(state, op, type, items, origin) when op in ["keep_hashed", "unsync_hashed"] do
    Enum.reduce(items, state, fn %{"hashes" => hashes, "salt" => salt}, acc ->
      named = MapSet.new(hashes)

      dropped =
        for id <- held_ids(acc, type),
            MapSet.member?(named, Frame.drop_hash(salt, id)) == (op == "unsync_hashed"),
            do: id

      drop_rows(acc, type, dropped, origin)
    end)
  end

  defp apply_group(state, op, type, items, origin) do
    Enum.reduce(items, state, &apply_one(&2, op, type, &1, origin))
  end

  defp apply_one(state, "add_relationship", type, item, _origin) do
    update_fact(
      state,
      {type, item["relationship"]},
      item["id"],
      &MapSet.put(&1, item["target_id"])
    )
  end

  defp apply_one(state, "del_relationship", type, item, _origin) do
    update_fact(
      state,
      {type, item["relationship"]},
      item["id"],
      &MapSet.delete(&1, item["target_id"])
    )
  end

  defp apply_one(state, op, type, id, _origin) when op in ["del_entity", "unsync_entity"] do
    delete_row(state, type, id)
  end

  # A patch merges into the row the client holds, and is passed over for one it doesn't: it
  # names a row the client was told about, so an unheld one is a row it was already told to let go.
  # Recorded either way, since the server sent the row's values.
  defp apply_one(state, "patch_entity", type, changes, origin) do
    case get_in(state.tables, [type, changes["id"]]) do
      nil ->
        record(state, type, changes, origin, false)

      held ->
        state
        |> file_row(type, Map.merge(held, changes))
        |> record(type, changes, origin, true)
    end
  end

  defp apply_one(state, "put_entity", type, row, origin) do
    state
    |> file_row(type, row)
    |> Map.update!(:awaiting, &MapSet.delete(&1, {type, row["id"]}))
    |> record(type, row, origin, true)
  end

  # A row's sets go to the facts, replacing what was filed under it, and the rest of it to its
  # type's table - what `Deltas.#fileRow` does.
  defp file_row(state, type, row) do
    set_names = set_names(model_type(type))
    {sets, attributes} = Map.split(row, set_names)

    filed = put_in(state, [Access.key(:tables), Access.key(type, %{}), row["id"]], attributes)

    Enum.reduce(sets, filed, fn {name, ids}, acc ->
      update_fact(acc, {type, name}, row["id"], fn _filed -> MapSet.new(ids) end)
    end)
  end

  # A row dropped by hash also takes every pair filed under a held row naming it, since the server,
  # not knowing the client held it, tells nothing of those pairs - `Deltas.#dropRows`.
  defp drop_rows(state, _type, [], _origin), do: state

  defp drop_rows(state, type, ids, _origin) do
    dropped = Enum.reduce(ids, state, &delete_row(&2, type, &1))
    named = MapSet.new(ids)

    for {holder_type, name} <- facts_naming(type), reduce: dropped do
      acc ->
        acc
        |> held_ids(holder_type)
        |> Enum.reduce(acc, fn holder_id, holder_acc ->
          update_fact(holder_acc, {holder_type, name}, holder_id, &MapSet.difference(&1, named))
        end)
    end
  end

  defp delete_row(state, type, id) do
    facts =
      Map.new(state.facts, fn
        {{^type, _name} = key, by_source} -> {key, Map.delete(by_source, id)}
        other -> other
      end)

    # The row's awaiting mark stays, as the browser's carried mark does: a sweep takes it, and the
    # pairs an edge filed under the id since, along with it.
    %{state | facts: facts, tables: Map.update(state.tables, type, %{}, &Map.delete(&1, id))}
  end

  # Every held row goes back to awaiting the server's word, and the completeness marks go, so the
  # marker ending the fill sweeps whatever it never delivered - `LocalDatabase.beginRefill`.
  defp begin_refill(state) do
    held = for {type, rows} <- state.tables, id <- Map.keys(rows), do: {type, id}

    %{
      state
      | awaiting: MapSet.union(state.awaiting, MapSet.new(held)),
        synced_all: false,
        synced_types: MapSet.new()
    }
  end

  # Swept only the first time after a refill - `LocalDatabase.markAllSynced`.
  defp mark_all_synced(%{synced_all: true} = state), do: state

  defp mark_all_synced(state), do: sweep(%{state | synced_all: true}, fn _type -> true end)

  # Each type marked for the first time sweeps its awaiting rows, unless everything already came -
  # `LocalDatabase.markTypesSynced`.
  defp mark_types_synced(state, types) do
    marked =
      types
      |> MapSet.new()
      |> MapSet.difference(state.synced_types)

    synced = %{state | synced_types: MapSet.union(state.synced_types, marked)}

    if state.synced_all, do: synced, else: sweep(synced, &MapSet.member?(marked, &1))
  end

  defp sweep(state, picks?) do
    state.awaiting
    |> Enum.filter(fn {type, _id} -> picks?.(type) end)
    |> Enum.reduce(state, fn {type, id} = key, acc ->
      acc
      |> delete_row(type, id)
      |> Map.update!(:awaiting, &MapSet.delete(&1, key))
    end)
  end

  defp reset(state) do
    %{
      state
      | awaiting: MapSet.new(),
        facts: %{},
        synced_all: false,
        synced_types: MapSet.new(),
        tables: %{}
    }
  end

  # Kept as the browser keeps it, and checked the way the server reads one back: one its decoding
  # can't read fails the run, whether a deltas frame or a marker carried it.
  defp keep_cursor(state, nil), do: state

  defp keep_cursor(state, cursor) do
    case cursor_tx(cursor) do
      {:ok, _tx} ->
        %{state | cursor: cursor}

      :error ->
        event(%{state | cursor: cursor}, :failure, %{cursor: cursor, failure: "unreadable cursor"})
    end
  end

  defp record(state, type, data, {cursor, received_at}, applied?) do
    case model_type(type) do
      nil ->
        state

      module ->
        record = %{
          applied?: applied?,
          carried: Map.take(data, Model.fields(module)),
          cursor_tx: bound_tx(cursor),
          id: data["id"],
          opened_at: state.opened_at,
          received_at: received_at,
          type: module
        }

        %{state | records: [record | state.records]}
    end
  end

  # A bound check 2 can't read is a failure where the cursor was kept, so the record goes without
  # one and is still checked against the other two bounds.
  defp bound_tx(cursor) do
    case cursor_tx(cursor) do
      {:ok, tx} -> tx
      :error -> nil
    end
  end

  # The transaction id a cursor names - opaque to a browser, read here because check 2 bounds what a
  # frame may carry by it, and read the way the server reads one back, so a change to the format
  # shows up as a failure where the cursor is kept rather than quietly switching the bound off.
  defp cursor_tx(nil), do: {:ok, nil}

  defp cursor_tx(cursor) do
    case Cursor.decode(cursor) do
      {:ok, tx, _seq, _policy_hash, _types_hash} -> {:ok, tx}
      :error -> :error
    end
  end

  defp comparable_store(state) do
    Map.new(Model.types(), fn module ->
      type = wire_type(module)

      rows =
        state.tables
        |> Map.get(type, %{})
        |> Map.new(fn {id, attributes} -> {id, comparable_row(state, module, id, attributes)} end)

      {module, rows}
    end)
  end

  defp comparable_row(state, module, id, attributes) do
    type = wire_type(module)

    sets =
      module
      |> Model.sets()
      |> Map.new(fn {name, _target} -> {name, filed_ids(state, type, name, id)} end)

    attributes
    |> Map.take(Model.fields(module))
    |> Map.merge(sets)
  end

  defp event(state, kind, details) do
    entry = Map.merge(details, %{at: System.monotonic_time(), kind: kind})

    %{state | events: [entry | state.events]}
  end

  # The facts a dropped row of the given type can be named by: a to-many of that type, and an
  # inverse of a to-many from it - a card's tags for a tag, a tag's cards for a card.
  defp facts_naming(type) do
    for module <- Model.types(),
        {name, target} <- Model.sets(module),
        wire_type(target) == type,
        do: {wire_type(module), name}
  end

  defp field(%Jason.OrderedObject{values: values}, name) do
    case List.keyfind(values, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp filed_ids(state, type, name, id) do
    state.facts
    |> Map.get({type, name}, %{})
    |> Map.get(id, MapSet.new())
    |> Enum.sort()
  end

  defp held_ids(state, type) do
    state.tables
    |> Map.get(type, %{})
    |> Map.keys()
  end

  defp model_type(type) do
    Enum.find(Model.types(), &(wire_type(&1) == type))
  end

  defp ops_summary(frame) do
    for {op, by_type} <- pairs(field(frame, "deltas")),
        {type, items} <- pairs(by_type),
        do: {op, type, length(items)}
  end

  defp pairs(nil), do: []

  defp pairs(%Jason.OrderedObject{values: values}), do: values

  # An item as a map, its nested objects too - only a frame's groups keep their order.
  defp plain(%Jason.OrderedObject{values: values}),
    do: Map.new(values, fn {key, value} -> {key, plain(value)} end)

  defp plain(values) when is_list(values), do: Enum.map(values, &plain/1)

  defp plain(value), do: value

  defp set_names(nil), do: []

  defp set_names(module) do
    module
    |> Model.sets()
    |> Map.keys()
  end

  defp update_fact(state, key, source_id, fun) do
    update_in(
      state,
      [Access.key(:facts), Access.key(key, %{}), Access.key(source_id, MapSet.new())],
      fun
    )
  end

  defp wire_type(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end
end
