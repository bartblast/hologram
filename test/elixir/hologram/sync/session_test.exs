defmodule Hologram.Sync.SessionTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.PLT
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Session
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1

  use_module_stub :query_cache
  use_module_stub :sync_page_windows

  setup :set_mox_global

  @board_window "w_board"
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
    |> DB.create()
  end

  # An evaluator reads from its own process, which the sandbox owner must let in before it runs
  # anything - otherwise it reaches the pool rather than this test's transaction and finds none of
  # these rows. Holding the windows first is what puts the evaluators there to be let in: the
  # session then finds them running and asks them for its first round.
  defp hold_windows(window_ids) do
    holder = spawn_link(fn -> Process.sleep(:infinity) end)

    Enum.each(window_ids, fn window_id ->
      {:ok, evaluator, _version} = Evaluators.subscribe(window_id, holder)

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
      hold_windows([@board_window, @other_window])

      # The other page's window is put beyond the store's reach, so nothing will ever fill it -
      # which is what leaves the rest of the build outstanding for as long as this test looks.
      Evaluator.round(@other_window, [])
      wait_until(fn -> ResultStore.versions(@other_window) == [1] end)
      ResultStore.forget(@other_window)

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

      assert_receive {:sync_deltas, deltas}

      assert deltas == [
               %{
                 data: task,
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
      refute_receive {:sync_deltas, _deltas}, 100
    end

    test "sends only the rows this client may read" do
      user =
        Module14
        |> Entity.new(email: "reader@example.com")
        |> DB.create()

      readable =
        PolicyModule1
        |> Entity.new(public: true)
        |> DB.create()

      PolicyModule1
      |> Entity.new()
      |> DB.create()

      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(actor_user_id: user.id)

      assert_receive {:sync_deltas, deltas}
      assert [%{data: ^readable, op: :put_entity}] = deltas
    end

    test "sends an anonymous visitor the rows anyone may read, and no others" do
      readable =
        PolicyModule1
        |> Entity.new(public: true)
        |> DB.create()

      PolicyModule1
      |> Entity.new()
      |> DB.create()

      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!([])

      assert_receive {:sync_deltas, deltas}
      assert [%{data: ^readable, op: :put_entity}] = deltas
    end

    test "says it is done once every window has sent its rows" do
      create("first")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_deltas, _board_deltas}
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
      assert_receive {:sync_deltas, _first_deltas}

      test_pid = self()
      other_client = spawn_link(fn -> forward(test_pid) end)

      start_session!(client: other_client)

      assert_receive {:forwarded, {:sync_deltas, deltas}}
      assert [%{data: ^task, op: :put_entity}] = deltas
      assert ResultStore.versions(@board_window) == [1]
    end
  end

  describe "handle :round" do
    test "sends what changed for this client, valued from the round" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _first_deltas}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]))

      assert_receive {:sync_deltas, deltas}
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

      assert_receive {:sync_deltas, deltas}
      assert [%{data: ^task, op: :put_entity}] = deltas
    end

    test "tells the client to drop a row that left the only window holding it" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _first_deltas}

      DB.delete(Module2, task.id)
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, deltas}

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
      assert_receive {:sync_deltas, _first_deltas}

      Evaluator.round(@board_window, [])

      refute_receive {:sync_deltas, _deltas}, 100
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
      assert_receive {:sync_deltas, _board_deltas}
      assert_receive {:sync_deltas, _other_deltas}

      # The row leaves one window without leaving the database, so the other still carries it -
      # and a client that keeps the row has been told nothing, which is no frame at all.
      DB.update(Module2, task.id, %{a: false})
      Evaluator.round(@other_window, transactions(task.id, ["a"]))

      refute_receive {:sync_deltas, _deltas}, 100
    end

    test "drops a row once it has left every window holding it" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])
      assert_receive {:sync_deltas, _board_deltas}
      assert_receive {:sync_deltas, _other_deltas}

      DB.delete(Module2, task.id)

      # Gone from one window, still held through the other - nothing to tell the client yet.
      Evaluator.round(@other_window, [])
      refute_receive {:sync_deltas, _other_deltas}, 100

      # Gone from the last window holding it, so now it leaves the client too.
      Evaluator.round(@board_window, [])
      assert_receive {:sync_deltas, board_deltas}
      assert [%{id: unsynced_id, op: :unsync_entity}] = board_deltas
      assert unsynced_id == task.id
    end
  end

  defp forward(test_pid) do
    receive do
      message ->
        send(test_pid, {:forwarded, message})

        forward(test_pid)
    end
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
