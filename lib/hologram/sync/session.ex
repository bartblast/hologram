defmodule Hologram.Sync.Session do
  @moduledoc false

  # One per connected client. It holds what that client has been told - which rows, of which
  # windows - and turns each shared round into the part of it that is this client's news.
  #
  # What it keeps is membership, never rows: the rows live once per node in the result store,
  # and a hundred sessions reading one window read that one copy.
  #
  # A client is given every window this build downloads, not only the ones its page reads: a page
  # it navigates to is then answered from what it already has, with no server in the way. The page
  # decides ORDER - its own windows fill first, the rest follow - so what the client is looking at
  # is ready first and the rest arrives while it reads.

  use GenServer, restart: :temporary

  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Diff
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Frame
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore

  @doc """
  Starts a session for a client on the given `:page`, telling `:client` what changes for it.

  `:actor_user_id` is who the client is, or nil for an anonymous one - every row is checked
  against it before being sent, so what the client named as its page decides only the order the
  windows fill in, never what it may see of them.

  `:fill_place` is where the log stood when this session's windows were taken up - what every
  window's place starts at, so a window that has had no round of its own still holds the frames
  back to a place its rows are known to cover. Without it a batch already routed but not yet
  delivered would fall outside every claim a frame makes.

  A frame carries the place the client may resume from only once it holds a whole pot: mid-fill
  there is nothing coherent to resume from, and a place handed over early is a claim the client
  cannot honour.

  `:gap` is what a returning client missed - absent for one arriving with nothing, in which case
  every row it may see is sent. Given a gap, the client keeps what it already holds and is told
  only about the rows the gap names. Whether a gap can be had at all is decided before the session
  starts, since it is a question about the log rather than about this client.

  Windows that nothing downloads are skipped rather than refused, which is how a client naming a
  page this build does not have still gets the rest of the build's windows.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(opts) do
    # Read once and asked about once: whether this client is resuming IS whether it arrived with a
    # gap, and two reads of the same option are two chances for them to say different things.
    gap = Keyword.get(opts, :gap)

    state = %{
      actor_user_id: Keyword.get(opts, :actor_user_id),
      announced: MapSet.new(),
      client: Keyword.fetch!(opts, :client),
      fill_place: Keyword.get(opts, :fill_place),
      gap: gap,
      held: %{},
      page: Keyword.fetch!(opts, :page),
      page_windows: MapSet.new(),
      pending: MapSet.new(),
      places: %{},
      resuming: gap != nil,
      touched: %{}
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, state) do
    page_window_ids = PageWindows.lookup(state.page)
    background_window_ids = PageWindows.all() -- page_window_ids
    window_ids = page_window_ids ++ background_window_ids

    # Every window counts as outstanding before any of them is taken up, so one that fills while
    # the others are still being taken up cannot empty the set and say the client has everything.
    seeded = %{
      state
      | page_windows: MapSet.new(page_window_ids),
        pending: MapSet.new(window_ids),
        places: Map.new(window_ids, &{&1, state.fill_place})
    }

    # A client with nothing to wait for is told so at once: one left waiting for a marker that
    # never comes would never read its own store.
    subscribed = Enum.reduce(window_ids, announce(seeded), &subscribe_to_window/2)

    {:noreply, subscribed}
  end

  @impl GenServer
  def handle_info(:behind_the_ring, state) do
    {:stop, :behind_the_ring, state}
  end

  # An evaluator this session was reading has stopped, and nothing else will arrive for its window
  # - the same cliff as a round falling out of the ring, and taken the same way. Cut rather than
  # repaired in place: what stopped it is not known here, and the reason that matters most - the
  # whole sync unit going down with the database - takes the registry and the stored rows too, so
  # there is nothing left to rejoin. The client comes back through the doors instead, where its
  # model, its place and the size of its gap are all read again rather than assumed.
  def handle_info({:DOWN, _ref, :process, _evaluator, _reason}, state) do
    {:stop, :evaluator_gone, state}
  end

  def handle_info({:round, window_id, version, transactions, place}, state) do
    updated = remember_place(state, window_id, place)

    {:noreply, deliver(updated, window_id, version, transactions)}
  end

  defp deliver(state, window_id, version, transactions) do
    case ResultStore.fetch(window_id, version) do
      # The round fell out of the ring before this session read it, so this client is further
      # behind than the store reaches - the same cliff as coming back to a log that no longer
      # covers you, and answered the same way: the connection is cut and the client comes back
      # through the doors like any returning one. Cutting is what the session HAS to do rather
      # than filling again in place, because what it holds is what the client was told, and a
      # round it cannot read leaves it unable to say what that still is.
      #
      # Deferred rather than stopped here, so every caller of this can carry on returning state.
      nil ->
        send(self(), :behind_the_ring)

        state

      result ->
        held = Map.get(state.held, window_id, %{})

        held_ids =
          held
          |> Map.keys()
          |> MapSet.new()

        deltas = Diff.deltas(result, held_ids, state.actor_user_id, transactions)

        state
        |> send_deltas(window_id, deltas)
        |> remember(window_id, held, deltas)
        |> mark_filled(window_id)
    end
  end

  # A row is dropped only once it has left every window this client holds - one window losing it
  # while another still carries it is not news, and telling the client to drop it would take the
  # row out from under the query that still wants it. What a window holds is the whole of its
  # REACH: a row carried only through an include counts the same as a root.
  defp left_the_pot(state, window_id, vanished) do
    others = Map.delete(state.held, window_id)

    Enum.reject(vanished, fn id ->
      Enum.any?(others, fn {_window_id, held} -> Map.has_key?(held, id) end)
    end)
  end

  # A client being caught up is told nothing until it is: what it holds is stale until the gap
  # lands, and a marker saying otherwise would have it read a store that lies. Once every window
  # has reported, what the client may see is known, and the gap can be spoken.
  defp announce(state) do
    cond do
      not replaying?(state) ->
        announce_scopes(state)

      Enum.empty?(state.pending) ->
        state
        |> catch_up()
        |> announce_scopes()

      true ->
        state
    end
  end

  # Two scopes rather than one marker per window: what a client needs to know is whether it can
  # answer a page from its own store, and window ids are the server's business - they never cross
  # the wire. `:page` means the page the client is on is answerable, `:all` means every page is.
  defp announce_scopes(state) do
    state
    |> announce_scope(:page)
    |> announce_scope(:all)
  end

  defp announce_scope(state, scope) do
    filled? =
      state
      |> outstanding(scope)
      |> Enum.empty?()

    if filled? and not MapSet.member?(state.announced, scope) do
      send(state.client, {:sync_synced, scope})

      %{state | announced: MapSet.put(state.announced, scope)}
    else
      state
    end
  end

  # What the client missed, told from the rows as they stand now rather than from the log's own
  # account of them. Everything it holds that the gap never touched is still true, and is left
  # alone - which is the whole saving over sending it the lot.
  defp catch_up(state) do
    state.gap
    |> Enum.chunk_every(Catchup.rows_per_frame())
    |> Enum.each(&tell_batch(state, &1))

    %{state | gap: nil, touched: %{}}
  end

  # Each batch claims ITS OWN last place rather than the whole gap's, which is what makes a replay
  # resumable: a client cut off after three of ten batches comes back dated to the third and is
  # given the rest, instead of starting the gap again. The batches are read in log order, so the
  # place of a batch's last effect is a place everything before it has been applied to.
  defp tell_batch(state, effects) do
    deltas = Catchup.deltas(effects, state.touched)

    if deltas != [] do
      send(state.client, {:sync_deltas, batch_cursor(state, effects), deltas})
    end
  end

  defp batch_cursor(state, effects) do
    if holds_a_whole_pot?(state) do
      %{seq: seq, tx: tx} = List.last(effects)

      Cursor.encode(tx, seq)
    end
  end

  defp mark_filled(state, window_id) do
    filled = %{state | pending: MapSet.delete(state.pending, window_id)}

    announce(filled)
  end

  defp outstanding(state, :all), do: state.pending

  defp outstanding(state, :page) do
    MapSet.intersection(state.pending, state.page_windows)
  end

  # What a frame may claim the client has reached: the SLOWEST window's place. A window's missed
  # changes can only live in batches after its last applied round, and those start at or above
  # that round's place - so replaying from the minimum covers every window's possible gap, whatever
  # order the rounds arrived in. Claiming the newest place instead would lose a slow window's
  # changes outright, which no amount of idempotent replay puts back.
  defp cursor(state) do
    if holds_a_whole_pot?(state) do
      place =
        state.places
        |> Map.values()
        |> Enum.reject(&is_nil/1)
        |> Enum.min(fn -> nil end)

      case place do
        nil -> nil
        {tx, seq} -> Cursor.encode(tx, seq)
      end
    end
  end

  # A cursor is a CLAIM - "everything up to here is applied" - and the server takes it at face
  # value on the way back, replaying only what came after. A client part way through its first fill
  # cannot make that claim: it holds some windows and not others, and handing it a place would have
  # it come back asking for the little that changed since, never learning about the windows it
  # never received. Silently, and for as long as it keeps that store.
  #
  # So frames carry no place until the client has a whole pot to date it - which is true from the
  # start for one that arrived WITH a gap, since it kept what it already had, and true for a first
  # arrival once every window has reported.
  defp holds_a_whole_pot?(state) do
    state.resuming or MapSet.member?(state.announced, :all)
  end

  # The last place each window has applied, taken forward only - a slow round arriving late must
  # not drag a window's place backwards, and both claims it could make are sound, so the further
  # one is kept. What a frame may claim is the MINIMUM of these: a window's missed changes can
  # only live in batches after its last applied round, so replaying from the slowest window's
  # place covers every window's possible gap. A fill round carries no place and changes nothing.
  defp remember_place(state, _window_id, nil), do: state

  defp remember_place(state, window_id, place) do
    places = Map.update(state.places, window_id, place, &max(&1, place))

    %{state | places: places}
  end

  # Each id is held under its type, because a row that later leaves is no longer there to name
  # its own - the arrival is the one moment the type is in hand, so it is kept from there.
  defp remember(state, window_id, held, deltas) do
    arrived = Map.new(deltas.appeared, &{&1.id, &1.__struct__})

    window_held =
      held
      |> Map.merge(arrived)
      |> Map.drop(deltas.vanished)

    %{state | held: Map.put(state.held, window_id, window_held)}
  end

  defp replaying?(state), do: state.gap != nil

  # While a client is being caught up nothing goes out, so the gap cannot be undone by a round
  # that reaches it first. What the rounds are read for is the rows the gap names - and only
  # those, so what is held here is bounded by what moved rather than by what the client holds.
  defp remember_touched(state, deltas) do
    touched_ids = MapSet.new(state.gap, & &1.entity_id)

    rows =
      deltas.patched
      |> Enum.map(fn {row, _patch} -> row end)
      |> Enum.concat(deltas.appeared)
      |> Enum.filter(&MapSet.member?(touched_ids, &1.id))
      |> Map.new(&{&1.id, &1})

    %{state | touched: Map.merge(state.touched, rows)}
  end

  defp send_deltas(state, window_id, deltas) do
    if replaying?(state) do
      remember_touched(state, deltas)
    else
      tell(state, window_id, deltas)
    end
  end

  defp tell(state, window_id, deltas) do
    held = Map.get(state.held, window_id, %{})
    unsynced = left_the_pot(state, window_id, deltas.vanished)

    news = %{
      appeared: deltas.appeared,
      edges: deltas.edges,
      patched: deltas.patched,
      unsynced: Enum.map(unsynced, &{&1, Map.fetch!(held, &1)})
    }

    news
    |> split_news()
    |> Enum.each(fn part ->
      send(state.client, {:sync_deltas, cursor(state), Frame.deltas(part)})
    end)

    state
  end

  # A window's first round hands over every row the client may see of it, and a whole window in one
  # frame is a frame as big as the app's data - the memory it costs is unbounded in exactly the way
  # a replay's was. Rows that APPEARED are the part that grows, so they are split across frames and
  # everything else rides with the first.
  #
  # Nothing here dates a partial fill: `cursor/1` already answers nil until the client holds a whole
  # pot, so a client cut off between two of these frames comes back with no place and is filled
  # again. That is the honest answer while the frames are all a client has - it cannot yet say what
  # it kept.
  #
  # TODO: step 07 owns what a client DOES with a partial fill, and may want more from these frames
  # than they carry - a marker saying which window a batch belongs to, or how many are still coming,
  # so a store can commit progress rather than discarding it on a cut connection. Settle that
  # against the local store's design rather than guessing here: the shape is cheap to add and
  # expensive to change once a client reads it.
  #
  # TODO: a resync's fill is the same code path, so the same question applies to what a client
  # discards and when. Today it discards on the marker and refills from nothing.
  defp split_news(news) do
    case Enum.chunk_every(news.appeared, Catchup.rows_per_frame()) do
      [] ->
        if news == %{appeared: [], edges: [], patched: [], unsynced: []}, do: [], else: [news]

      [first | rest] ->
        [%{news | appeared: first}] ++
          Enum.map(rest, &%{appeared: &1, edges: [], patched: [], unsynced: []})
    end
  end

  defp subscribe_to_window(window_id, state) do
    case Evaluators.subscribe(window_id, self()) do
      # Nothing downloads it, so nothing will ever arrive for it - which is as filled as it will
      # ever be, and waiting on it would leave the client waiting forever.
      :no_window ->
        # Its place is dropped along with it. What a frame claims is the place of the window
        # furthest behind, and a window that will never have a round never moves - so left among
        # them it would hold every claim at the place this session started from. The client would
        # replay from there on each reconnect, from further back every time, until the gap outgrew
        # what the log still covers and it was sent everything again. A window with no rounds has
        # no missed changes for a claim to cover.
        unconstrained = %{state | places: Map.delete(state.places, window_id)}

        mark_filled(unconstrained, window_id)

      {:ok, evaluator, version, _term} ->
        # Watched from here on: an evaluator that stops is the end of a window's rounds, and a
        # session not told would hold that window pending for as long as the client stayed - never
        # announcing a scope, never sending a marker, with nothing the client could do about it.
        Process.monitor(evaluator)

        first_round(state, window_id, version)
    end
  end

  defp first_round(state, window_id, 0) do
    Evaluator.round(window_id, [])

    state
  end

  defp first_round(state, window_id, version), do: deliver(state, window_id, version, [])
end
