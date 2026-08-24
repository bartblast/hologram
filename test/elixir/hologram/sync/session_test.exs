defmodule Hologram.Sync.SessionTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Query, only: [add_relationship: 3, delete_relationship: 3]
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.PLT
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Session
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1

  use_module_stub :query_cache
  use_module_stub :sync_page_windows

  setup :set_mox_global

  @board_window "w_board"
  @include_window "w_include"
  @other_page MyApp.SettingsPage
  @other_window "w_other"
  @page MyApp.BoardPage

  setup do
    setup_query_cache(QueryCacheStub, false)
    setup_sync_page_windows(SyncPageWindowsStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      entries: %{},
      prop_params: %{},
      windows: %{
        @board_window => Query.normalize(Module2),
        @other_window => Query.normalize(PolicyModule1)
      }
    })

    wait_for_process_cleanup(ResultStore)
    start_supervised!(ResultStore)

    wait_for_process_cleanup(Evaluator.registry())
    start_supervised!({Registry, keys: :unique, name: Evaluator.registry()})

    wait_for_process_cleanup(Evaluators)
    start_supervised!(Evaluators)

    :ok
  end

  defp create(title) do
    Module2
    |> Entity.new(a: true, c: title)
    |> DB.create!()
  end

  # One entry of what a returning client missed, in the shape the log reports it - the place
  # included, since a replay dates each batch it sends by the last effect in it.
  defp gap_effect(entity_id, place \\ {200, 0}) do
    {tx, seq} = place

    %{entity_id: entity_id, op: :patch_entity, seq: seq, tx: tx, type: Module2}
  end

  # Takes a window's place in the registry with a process that answers a subscription and then says
  # nothing more, which leaves the window outstanding rather than filled or failed.
  defp hold_silently(window_id) do
    silent =
      spawn_link(fn ->
        {:ok, _pid} = Registry.register(Evaluator.registry(), window_id, nil)

        silence()
      end)

    wait_until(fn -> Registry.lookup(Evaluator.registry(), window_id) == [{silent, nil}] end)

    silent
  end

  # An evaluator reads from its own process, which the sandbox owner must let in before it runs
  # anything - otherwise it reaches the pool rather than this test's transaction and finds none of
  # these rows. Holding the windows first is what puts the evaluators there to be let in: the
  # session then finds them running and asks them for its first round.
  defp hold_windows(window_ids) do
    holder = spawn_link(fn -> Process.sleep(:infinity) end)

    Enum.each(window_ids, fn window_id ->
      {:ok, evaluator, _version, _term} = Evaluators.subscribe(window_id, holder)

      DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), evaluator, [])
    end)

    holder
  end

  defp start_session!(opts) do
    opts =
      opts
      |> Keyword.put_new(:client, self())
      |> Keyword.put_new(:page, @page)

    start_supervised!(Supervisor.child_spec({Session, opts}, id: make_ref()))
  end

  # The page windows are a build artifact read from a dump file, so a test says what the build
  # worked out by writing one and letting the registry read it.
  defp windows(page_windows) do
    dump_path = SyncPageWindowsStub.dump_path()

    File.rm(dump_path)

    dump_path
    |> Path.dirname()
    |> File.mkdir_p!()

    page_windows
    |> Enum.reduce(PLT.start(), fn {page, window_ids}, plt -> PLT.put(plt, page, window_ids) end)
    |> PLT.dump(dump_path)

    PageWindows.init(nil)

    :ok
  end

  describe "start_link/1 - registration" do
    test "holds the windows its page reaches" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])

      assert_receive {:sync_synced, :page}
      assert Evaluators.live() == [{@board_window, Query.normalize(Module2)}]
    end

    test "holds every window its page reaches" do
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :page}

      live_window_ids =
        Evaluators.live()
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert live_window_ids == [@board_window, @other_window]
    end

    test "holds nothing for a page this build does not have" do
      windows(%{})

      start_session!([])

      assert_receive {:sync_synced, :page}
      assert Evaluators.live() == []
    end

    test "skips a window nothing downloads rather than refusing to start" do
      windows(%{@page => ["w_unknown", @board_window]})
      hold_windows([@board_window])

      session = start_session!([])

      assert_receive {:sync_synced, :page}
      assert Process.alive?(session)
      assert Evaluators.live() == [{@board_window, Query.normalize(Module2)}]
    end

    test "joins the window a session already holds rather than starting a second evaluator" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_synced, :page}

      other_client = spawn_link(fn -> Process.sleep(:infinity) end)

      start_session!(client: other_client)

      assert length(Evaluators.live()) == 1
    end
  end

  describe "start_link/1 - coming back" do
    test "tells a returning client only about the rows the gap names" do
      moved = create("moved while away")
      untouched = create("untouched while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [gap_effect(moved.id)])

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.c == moved.c

      refute_receive {:sync_deltas, _cursor, _more}, 100
      refute Enum.any?(deltas, &(&1.id == untouched.id))
    end

    # A gap arrives in batches rather than one frame, so the memory a replay costs is bounded by
    # the batch rather than by how long the client was away - and each batch is dated by its own
    # last effect, so a client cut off part way comes back to the rest instead of the whole gap.
    test "replays a gap in batches, each dated by its own last effect" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      put_app_env(:sync, rows_per_frame: 2)

      # Two per frame rather than one, so the place a batch claims is its LAST effect and not
      # merely its only one.
      gap =
        Enum.map(1..4, fn seq ->
          entity_id = if seq == 1, do: moved.id, else: Entity.generate_id()

          gap_effect(entity_id, {900, seq})
        end)

      start_session!(fill_place: {200, 0}, gap: gap)

      assert_receive {:sync_deltas, first_cursor, first_deltas}
      assert Cursor.decode(first_cursor) == {:ok, 900, 2}
      assert length(first_deltas) == 2

      assert_receive {:sync_deltas, second_cursor, second_deltas}
      assert Cursor.decode(second_cursor) == {:ok, 900, 4}
      assert length(second_deltas) == 2
    end

    test "tells a returning client to drop a row it may no longer see" do
      create("still here")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      gone_id = Entity.generate_id()

      start_session!(gap: [gap_effect(gone_id)])

      assert_receive {:sync_deltas, _cursor, deltas}

      assert deltas == [
               %{
                 id: gone_id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "tells a returning client that missed nothing nothing at all" do
      create("unchanged while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [])

      assert_receive {:sync_synced, :all}
      refute_received {:sync_deltas, _cursor, _deltas}
    end

    test "says the pages are answerable only once what was missed has been told" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [gap_effect(moved.id)])

      # Received in this order, so the client never reads its own store while it is still stale.
      assert_receive {:sync_deltas, _cursor, _deltas}
      assert_receive {:sync_synced, :page}
    end

    test "keeps telling a returning client the news once it has been caught up" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [gap_effect(moved.id)])
      assert_receive {:sync_deltas, _cursor, _caught_up}

      DB.update(Module2, moved.id, %{c: "moved again, this time watched"})
      Evaluator.round(@board_window, transactions(moved.id, ["c"]))

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: patch, op: :patch_entity}] = deltas
      assert patch.c == "moved again, this time watched"
    end
  end

  describe "start_link/1 - a fill too big for one frame" do
    # A window's first round hands over every row the client may see of it, so one frame per window
    # is a frame as big as the app's data. Splitting it bounds what a frame costs by the batch
    # rather than by how much the app stores.
    test "splits a window's rows across frames" do
      Enum.each(1..3, &create("row #{&1}"))
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      put_app_env(:sync, rows_per_frame: 2)

      start_session!([])

      assert_receive {:sync_deltas, nil, first}
      assert length(first) == 2

      assert_receive {:sync_deltas, nil, second}
      assert length(second) == 1

      assert_receive {:sync_synced, :all}
    end

    # Everything that is not an appeared row rides with the first frame rather than being repeated:
    # a client applying the batches in order sees each of them once.
    test "sends what is not an appeared row once, with the first frame" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, nil, _fill}
      assert_receive {:sync_synced, :all}

      put_app_env(:sync, rows_per_frame: 2)

      # Three rows appear while the one the client holds changes, so the round splits across two
      # frames and the patch has somewhere it could wrongly be repeated.
      Enum.each(1..3, &create("appeared #{&1}"))
      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), nil)

      assert_receive {:sync_deltas, _first_cursor, first}
      assert_receive {:sync_deltas, _second_cursor, second}

      patches = Enum.count(first ++ second, &(&1.op == :patch_entity))
      assert patches == 1
      assert Enum.any?(first, &(&1.op == :patch_entity))
    end
  end

  describe "start_link/1 - completeness" do
    test "takes up the windows of pages the client is not on" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :all}

      live_window_ids =
        Evaluators.live()
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert live_window_ids == [@board_window, @other_window]
    end

    test "says the client's page is answerable while the rest is still arriving" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window])

      # The other page's window is held by an evaluator that never answers, so the rest of the
      # build stays outstanding for as long as this test cares to look.
      hold_silently(@other_window)

      start_session!([])

      assert_receive {:sync_synced, :page}
      refute_receive {:sync_synced, :all}, 100
    end

    test "says every page is answerable once the last window has filled" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :page}
      assert_receive {:sync_synced, :all}
    end

    test "says a page reading nothing is answerable at once, and waits for the rest" do
      windows(%{@other_page => [@other_window]})
      hold_windows([@other_window])

      start_session!([])

      assert_receive {:sync_synced, :page}
      assert_receive {:sync_synced, :all}
    end

    test "says both at once for a build downloading nothing" do
      windows(%{})

      start_session!([])

      assert_receive {:sync_synced, :page}
      assert_receive {:sync_synced, :all}
    end

    test "says each scope once, however many windows fill after it" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :page}
      assert_receive {:sync_synced, :all}

      Evaluator.round(@board_window, [])
      Evaluator.round(@other_window, [])

      refute_receive {:sync_synced, _scope}, 100
    end
  end

  describe "start_link/1 - first rows" do
    test "sends the rows the window holds" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])

      assert_receive {:sync_deltas, _cursor, deltas}

      assert deltas == [
               %{
                 data: WireData.row(task),
                 id: task.id,
                 op: :put_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "sends nothing for a window holding no rows" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])

      assert_receive {:sync_synced, :page}
      refute_receive {:sync_deltas, _cursor, _deltas}, 100
    end

    test "sends only the rows this client may read" do
      user =
        Module14
        |> Entity.new(email: "reader@example.com")
        |> DB.create!()

      readable =
        PolicyModule1
        |> Entity.new(public: true)
        |> DB.create!()

      PolicyModule1
      |> Entity.new()
      |> DB.create!()

      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(actor_user_id: user.id)

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == readable.id
    end

    test "sends an anonymous visitor the rows anyone may read, and no others" do
      readable =
        PolicyModule1
        |> Entity.new(public: true)
        |> DB.create!()

      PolicyModule1
      |> Entity.new()
      |> DB.create!()

      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!([])

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == readable.id
    end

    test "says it is done once every window has sent its rows" do
      create("first")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_deltas, _cursor, _board_deltas}
      assert_receive {:sync_synced, :page}
    end

    test "says it is done immediately for a page reaching no window" do
      windows(%{@page => []})

      start_session!([])

      assert_receive {:sync_synced, :page}
    end

    test "reads the round a running evaluator already has rather than asking for another" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas}

      test_pid = self()
      other_client = spawn_link(fn -> forward(test_pid) end)

      start_session!(client: other_client)

      assert_receive {:forwarded, {:sync_deltas, _cursor, deltas}}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == task.id
      assert ResultStore.versions(@board_window) == [1]
    end
  end

  describe "handle :DOWN" do
    # An evaluator that stops is the end of its window's rounds. A session not watching would hold
    # that window pending for as long as the client stayed - no scope announced, no marker sent -
    # or, once the pot was complete, go on claiming to be current while nothing arrived for the
    # window again. Cutting sends the client back through the doors, which is a path it has.
    #
    # The window killed here is not the first one taken up: every evaluator a session reads is
    # watched, not whichever it happened to start with.
    test "cuts the client off when an evaluator it reads stops" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      session = start_session!([])
      assert_receive {:sync_synced, :all}

      [{evaluator, _value}] = Registry.lookup(Evaluator.registry(), @other_window)

      ref = Process.monitor(session)
      Process.exit(evaluator, :kill)

      # The reason is what carries the connection with it: the session is linked to the process
      # holding the stream, so anything but a normal exit takes the stream down and the client
      # reconnects.
      assert_receive {:DOWN, ^ref, :process, ^session, :evaluator_gone}
    end
  end

  describe "handle :round" do
    test "sends what changed for this client, valued from the round" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]))

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: patch, id: id, op: :patch_entity}] = deltas
      assert id == task.id
      assert patch.c == "after"
    end

    test "sends a row that entered the window as it stands" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_synced, :page}

      task = create("appeared later")
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == task.id
    end

    test "tells the client to drop a row that left the only window holding it" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas}

      DB.delete(Module2, task.id)
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, _cursor, deltas}

      assert deltas == [
               %{
                 id: task.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "sends nothing when the round changed nothing for this client" do
      create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas}

      Evaluator.round(@board_window, [])

      refute_receive {:sync_deltas, _cursor, _deltas}, 100
    end
  end

  describe "handle :round - the place a frame claims" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        prop_params: %{},
        windows: %{
          @board_window => Query.normalize(Module2),
          @other_window => other_window_term()
        }
      })

      :ok
    end

    # A cursor is a claim the client has to be able to honour. Part way through a first fill it
    # holds some windows and not others, so a place handed over then would have it come back asking
    # only for what changed since - never learning about the windows it never received.
    test "claims no place while a first arrival is still being filled" do
      create("first")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0})

      assert_receive {:sync_deltas, cursor, _deltas}
      assert cursor == nil
    end

    test "claims the place its windows were taken up at once the pot is whole" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0})

      # The fill's own frame carries no place and has to be taken out of the way first.
      assert_receive {:sync_deltas, nil, _fill}
      assert_receive {:sync_synced, :all}

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), nil)

      assert_receive {:sync_deltas, cursor, _deltas}
      assert Cursor.decode(cursor) == {:ok, 200, 0}
    end

    # A returning client kept what it had, so it can date its store from the first frame - there is
    # no half-filled state for it to misreport. What it is dated BY is the last effect in the batch
    # rather than the fill place, which is what lets a replay be picked up where it stopped.
    test "dates each replayed batch by the last effect in it" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0}, gap: [gap_effect(moved.id, {900, 7})])

      assert_receive {:sync_deltas, cursor, _deltas}
      assert Cursor.decode(cursor) == {:ok, 900, 7}
    end

    # A window the page map reaches but the query cache no longer holds - what a live reload leaves
    # behind when it drops a query. It is skipped rather than refused, so it never has a round, and
    # its place would otherwise stay where the session started and hold every claim down with it:
    # the client would replay from further back on each reconnect until the log stopped reaching it.
    test "leaves a window nothing downloads out of the claim" do
      task = create("first")
      windows(%{@page => [@board_window, "w_nothing_downloads"]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0})

      assert_receive {:sync_deltas, nil, _fill}
      assert_receive {:sync_synced, :all}

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {900, 7})

      assert_receive {:sync_deltas, cursor, _deltas}
      assert Cursor.decode(cursor) == {:ok, 900, 7}
    end

    test "claims the place of the window furthest behind, not the one furthest ahead" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_deltas, _board_cursor, _board_deltas}
      assert_receive {:sync_deltas, _other_cursor, _other_deltas}

      # Only the board window advances. The other window is still back at the fill place, and a
      # frame claiming the board's place would tell the client it is caught up past changes the
      # other window has not delivered.
      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {900, 0})

      assert_receive {:sync_deltas, cursor, _deltas}
      assert Cursor.decode(cursor) == {:ok, 200, 0}
    end

    test "claims the newer place once every window has caught up to it" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_deltas, _board_cursor, _board_deltas}
      assert_receive {:sync_deltas, _other_cursor, _other_deltas}

      Evaluator.round(@other_window, [], {900, 0})

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {900, 0})

      assert_receive {:sync_deltas, cursor, _deltas}
      assert Cursor.decode(cursor) == {:ok, 900, 0}
    end

    # A round arriving out of order must not walk a window's place backwards: both places it could
    # claim are sound, so the further one is kept.
    test "keeps a window's place at the furthest a round has claimed for it" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_deltas, _first_cursor, _first_deltas}

      Evaluator.round(@board_window, [], {900, 0})

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {500, 0})

      assert_receive {:sync_deltas, cursor, _deltas}
      assert Cursor.decode(cursor) == {:ok, 900, 0}
    end
  end

  describe "handle :round - past the ring" do
    test "ends when told about a round the store no longer reaches" do
      create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      session = start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas}

      ref = Process.monitor(session)

      # A version the ring dropped before this session got to it.
      send(session, {:round, @board_window, 999, [], nil})

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
    end

    test "takes the connection with it, so the client comes back through the doors" do
      create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      test_pid = self()

      connection =
        spawn(fn ->
          {:ok, session} = Session.start_link(client: test_pid, page: @page)

          send(test_pid, {:connected, session})

          Process.sleep(:infinity)
        end)

      assert_receive {:connected, session}
      assert_receive {:sync_deltas, _cursor, _first_deltas}

      ref = Process.monitor(connection)
      send(session, {:round, @board_window, 999, [], nil})

      assert_receive {:DOWN, ^ref, :process, ^connection, :behind_the_ring}
    end
  end

  describe "handle :round - the pot" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        prop_params: %{},
        windows: %{
          @board_window => Query.normalize(Module2),
          @other_window => other_window_term()
        }
      })

      :ok
    end

    test "keeps a row the client still holds through another window" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _board_deltas}
      assert_receive {:sync_deltas, _cursor, _other_deltas}

      # The row leaves one window without leaving the database, so the other still carries it -
      # and a client that keeps the row has been told nothing, which is no frame at all.
      DB.update(Module2, task.id, %{a: false})
      Evaluator.round(@other_window, transactions(task.id, ["a"]))

      refute_receive {:sync_deltas, _cursor, _deltas}, 100
    end

    test "drops a row once it has left every window holding it" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _board_deltas}
      assert_receive {:sync_deltas, _cursor, _other_deltas}

      DB.delete(Module2, task.id)

      # Gone from one window, still held through the other - nothing to tell the client yet.
      Evaluator.round(@other_window, [])
      refute_receive {:sync_deltas, _cursor, _other_deltas}, 100

      # Gone from the last window holding it, so now it leaves the client too.
      Evaluator.round(@board_window, [])
      assert_receive {:sync_deltas, _cursor, board_deltas}
      assert [%{id: unsynced_id, op: :unsync_entity}] = board_deltas
      assert unsynced_id == task.id
    end
  end

  describe "handle :round - the pot over reach" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        prop_params: %{},
        windows: %{
          @board_window => Query.normalize(Module2),
          @include_window => include_window_term()
        }
      })

      :ok
    end

    test "keeps a child the client still holds through another window's reach" do
      child = create("held two ways")
      source = include_source(child)
      windows(%{@page => [@board_window, @include_window]})
      hold_windows([@board_window, @include_window])

      start_session!([])
      assert_receive {:sync_deltas, _board_cursor, _board_fill}
      assert_receive {:sync_deltas, _include_cursor, _include_fill}
      assert_receive {:sync_synced, :all}

      # The child leaves the include window's reach without leaving the database - the board
      # window still roots it, so the client keeps the row and is told nothing.
      source
      |> delete_relationship(:a, child.id)
      |> DB.update()

      Evaluator.round(@include_window, [])

      refute_receive {:sync_deltas, _cursor, _deltas}, 100
    end

    test "drops a child once it has left every reach holding it" do
      child = create("held two ways")
      source = include_source(child)
      windows(%{@page => [@board_window, @include_window]})
      hold_windows([@board_window, @include_window])

      start_session!([])
      assert_receive {:sync_deltas, _board_cursor, _board_fill}
      assert_receive {:sync_deltas, _include_cursor, _include_fill}
      assert_receive {:sync_synced, :all}

      source
      |> delete_relationship(:a, child.id)
      |> DB.update()

      Evaluator.round(@include_window, [])
      refute_receive {:sync_deltas, _cursor, _include_deltas}, 100

      DB.delete(Module2, child.id)
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{id: unsynced_id, op: :unsync_entity}] = deltas
      assert unsynced_id == child.id
    end

    test "names a dropped child by its own type, not the window's root type" do
      child = create("reached only through the include")
      source = include_source(child)
      windows(%{@page => [@include_window]})
      hold_windows([@include_window])

      start_session!([])
      assert_receive {:sync_deltas, _fill_cursor, _fill}
      assert_receive {:sync_synced, :all}

      source
      |> delete_relationship(:a, child.id)
      |> DB.update()

      Evaluator.round(@include_window, [])

      assert_receive {:sync_deltas, _cursor, deltas}

      assert deltas == [
               %{
                 id: child.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "replays a gap touching a row held only through reach" do
      child = create("moved while away")
      include_source(child)
      windows(%{@page => [@include_window]})
      hold_windows([@include_window])

      start_session!(gap: [gap_effect(child.id)])

      assert_receive {:sync_deltas, _cursor, deltas}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == child.id
    end
  end

  defp silence do
    receive do
      {:"$gen_call", from, {:subscribe, _subscriber}} ->
        GenServer.reply(from, {:ok, 0})

        silence()

      _round ->
        silence()
    end
  end

  defp forward(test_pid) do
    receive do
      message ->
        send(test_pid, {:forwarded, message})

        forward(test_pid)
    end
  end

  # A row of the include window's reach without being any window's root - what the child of the
  # reach tests is held through.
  defp include_source(child) do
    required =
      Module1
      |> Entity.new()
      |> DB.create!()

    source =
      Module3
      |> Entity.new(c_id: required.id)
      |> DB.create!()

    source
    |> add_relationship(:a, child.id)
    |> DB.update()

    source
  end

  defp include_window_term do
    Module3
    |> Query.include(:a)
    |> Query.normalize()
  end

  defp other_window_term do
    Module2
    |> Query.filter(a: true)
    |> Query.normalize()
  end

  defp transactions(entity_id, names) do
    data = Map.new(names, &{&1, "whatever the log said"})

    [{200, [%{op: :patch_entity, type: Module2, entity_id: entity_id, data: data}]}]
  end
end
