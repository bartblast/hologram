defmodule Hologram.Sync.SessionTest do
  # async: false - each test writes the query cache's persistent term, shared by the whole node,
  # and starts the sync result store, the evaluator registry and the evaluators supervisor under
  # their registered names, which one test on the node can hold at a time.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Query, only: [add_relationship: 3, delete_relationship: 3]
  import Hologram.Test.Stubs
  import Mox

  require Hologram.Query

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.PLT
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Frame
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Session
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyProject
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyLabel
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyParent
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5

  use_module_stub :query_cache
  use_module_stub :sync_page_windows

  setup :set_mox_global

  @bare_label_window "w_bare_label"
  @board_window "w_board"
  @other_replica_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"
  @include_window "w_include"
  @inverse_window "w_inverse"
  @label_window "w_label"
  @message_window "w_message"
  @other_page MyApp.SettingsPage
  @other_window "w_other"
  @page MyApp.BoardPage
  @policy_hash "0123456789abcdef0123456789abcdef"
  @project_window "w_project"
  @public_project_window "w_public_project"
  @reach_window "w_reach"
  @replica_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  setup do
    setup_query_cache(QueryCacheStub, false)
    setup_sync_page_windows(SyncPageWindowsStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      entries: %{},
      windows: %{
        @board_window => Stage.normalize(Module2),
        @other_window => Stage.normalize(PolicyModule1),
        @reach_window => Stage.normalize(PolicyModule5)
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
    %{a: true, c: title}
    |> Module2.new()
    |> DB.create!()
  end

  # One entry of what a returning client missed, in the shape the log reports it - the place
  # included, since a replay dates each batch it sends by the last effect in it.
  defp gap_effect(entity_id, place \\ {200, 0}, mutation_ref \\ nil) do
    {tx, seq} = place

    %{
      entity_id: entity_id,
      mutation_ref: mutation_ref,
      op: :patch_entity,
      revisions: nil,
      seq: seq,
      tx: tx,
      type: Module2
    }
  end

  # One entry naming a row of ANOTHER type, with the columns that moved on it - what decides
  # whether a row leaning on that one is worth judging again. Written as an override of the plain
  # entry rather than as more parameters on it, so the call sites read as what they are.
  defp related_effect(entity_id, type, revisions) do
    entity_id
    |> gap_effect()
    |> Map.merge(%{revisions: revisions, type: type})
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

  # Let into the sandbox the way an evaluator is, and for the same reason: the session reads the
  # grant store itself to decide what this client may see, so without this it judges every rule
  # against the committed database rather than against what the test wrote.
  #
  # Allowed after starting rather than before, since the pid is what is being allowed - the same
  # shape hold_windows/1 uses. The session's first read is several messages and a query past the
  # continue that starts it, so the allow is not on a knife edge.
  #
  # A test names what a returning client missed as `gap:` and, when its grants moved, `grants_then:`
  # - the effects and grants the session reads through `:read_gap`. They are handed over as a
  # reader answering them, dated by the gap's last effect as the read deciding the client resumes
  # dates it.
  defp start_session!(opts) do
    opts =
      opts
      |> resume_opts()
      |> Keyword.put_new(:client, self())
      |> Keyword.put_new(:page, @page)
      |> Keyword.put_new(:policy_hash, @policy_hash)

    session = start_supervised!(Supervisor.child_spec({Session, opts}, id: make_ref()))

    allow_into_sandbox(session)

    session
  end

  # A gap reader over the log lets the session in itself when the session calls it, which can be
  # before this test gets the chance - so being let in already is as good as letting it in.
  defp allow_into_sandbox(pid, owner \\ self()) do
    case DBConnection.Ownership.ownership_allow(DB.pool_name(), owner, pid, []) do
      :ok -> :ok
      {:already, :allowed} -> :ok
    end
  end

  defp resume_opts(opts) do
    {gap, without_gap} = Keyword.pop(opts, :gap)
    {grants_then, session_opts} = Keyword.pop(without_gap, :grants_then)

    cond do
      gap ->
        session_opts
        |> Keyword.put(:read_gap, fn -> {:ok, gap, grants_then} end)
        |> Keyword.put_new(:gap_end, gap_end(gap))

      grants_then ->
        raise ArgumentError, "grants_then: names the grants a gap starts from, so it needs a gap:"

      true ->
        session_opts
    end
  end

  defp gap_end([]), do: nil

  defp gap_end(gap) do
    %{seq: seq, tx: tx} = List.last(gap)

    {tx, seq}
  end

  # The place of the newest effect the log holds - what a client that last heard of it would come
  # back from.
  defp last_place do
    statement =
      ~s|SELECT "tx", "seq" FROM "hologram_system"."oplog" ORDER BY "tx" DESC, "seq" DESC LIMIT 1|

    {:ok, %Postgrex.Result{rows: [[tx, seq]]}} = Connection.query(statement)

    {tx, seq}
  end

  # A reader over the log, as the doors hand one over. It lets itself into the sandbox, since the
  # session calls it before a test could let the session in.
  defp read_gap_from(cursor, actor_user_id \\ nil) do
    test_pid = self()

    fn ->
      allow_into_sandbox(self(), test_pid)

      Catchup.gap(cursor, actor_user_id, @policy_hash)
    end
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

      assert_receive {:sync_synced, :page, _cursor}
      assert Evaluators.live() == [{@board_window, Stage.normalize(Module2)}]
    end

    test "holds every window its page reaches" do
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}

      live_window_ids =
        Evaluators.live()
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert live_window_ids == [@board_window, @other_window]
    end

    test "holds nothing for a page this build does not have" do
      windows(%{})

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
      assert Evaluators.live() == []
    end

    test "skips a window nothing downloads rather than refusing to start" do
      windows(%{@page => ["w_unknown", @board_window]})
      hold_windows([@board_window])

      session = start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
      assert Process.alive?(session)
      assert Evaluators.live() == [{@board_window, Stage.normalize(Module2)}]
    end

    test "joins the window a session already holds rather than starting a second evaluator" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_synced, :page, _cursor}

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

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.c == moved.c

      refute_receive {:sync_deltas, _cursor, _more, _applied_seq}, 100
      refute Enum.any?(deltas, &(&1.id == untouched.id))
    end

    # A client away long enough to need a replay may have had batches of its own applied while it
    # was gone - the gap is where it learns how far, since no round it can see carries them.
    test "raises the watermark from the batches of this replica in the gap" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      gap = [gap_effect(moved.id, {900, 1}, ref(@replica_id, 9))]

      start_session!(
        applied_seq: 3,
        fill_place: {200, 0},
        gap: gap,
        replica_id: @replica_id
      )

      assert_receive {:sync_deltas, _cursor, _deltas, 9}
    end

    # A write of this replica's own past what the deciding read found may be in no round the
    # session has read yet, so the frame carrying the row from before it can't say it is applied.
    test "raises the watermark no further than the read that decided the client resumes" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      gap = [
        gap_effect(moved.id, {900, 1}, ref(@replica_id, 4)),
        gap_effect(Entity.generate_id(), {900, 2}, ref(@replica_id, 9))
      ]

      start_session!(
        applied_seq: 3,
        fill_place: {200, 0},
        gap: gap,
        gap_end: {900, 1},
        replica_id: @replica_id
      )

      assert_receive {:sync_deltas, _cursor, _deltas, 4}
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

      assert_receive {:sync_deltas, first_cursor, first_deltas, _applied_seq}
      assert Cursor.decode(first_cursor) == {:ok, 900, 2, @policy_hash}
      assert length(first_deltas) == 2

      assert_receive {:sync_deltas, second_cursor, second_deltas, _applied_seq}
      assert Cursor.decode(second_cursor) == {:ok, 900, 4, @policy_hash}
      assert length(second_deltas) == 2
    end

    test "tells a returning client to drop a row it may no longer see" do
      create("still here")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      gone_id = Entity.generate_id()

      start_session!(gap: [gap_effect(gone_id)])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

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

      assert_receive {:sync_synced, :all, _cursor}
      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end

    test "says the pages are answerable only once what was missed has been told" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [gap_effect(moved.id)])

      # Received in this order, so the client never reads its own store while it is still stale.
      assert_receive {:sync_deltas, _cursor, _deltas, _applied_seq}
      assert_receive {:sync_synced, :page, _cursor}
    end

    test "keeps telling a returning client the news once it has been caught up" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [gap_effect(moved.id)])
      assert_receive {:sync_deltas, _cursor, _caught_up, _applied_seq}

      DB.update(Module2, moved.id, %{c: "moved again, this time watched"})
      Evaluator.round(@board_window, transactions(moved.id, ["c"]))

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: patch, op: :patch_entity}] = deltas
      assert patch.c == "moved again, this time watched"
    end

    # The gap read from the log itself rather than handed over, which is what a client coming back
    # through the doors is given.
    test "tells a returning client what the log says it missed" do
      moved = create("before leaving")
      untouched = create("untouched while away")
      {tx, seq} = last_place()
      cursor = Cursor.encode(tx, seq, @policy_hash)

      DB.update(Module2, moved.id, %{c: "moved while away"})

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      {gap_end_tx, gap_end_seq} = gap_end = last_place()

      start_supervised!(
        {Session,
         client: self(),
         gap_end: gap_end,
         page: @page,
         policy_hash: @policy_hash,
         read_gap: read_gap_from(cursor)}
      )

      assert_receive {:sync_deltas, frame_cursor, deltas, _applied_seq}
      assert Cursor.decode(frame_cursor) == {:ok, gap_end_tx, gap_end_seq, @policy_hash}
      assert [%{data: data, id: id, op: :put_entity}] = deltas
      assert id == moved.id
      assert data.c == "moved while away"

      refute Enum.any?(deltas, &(&1.id == untouched.id))
    end

    # The gap outgrew what a replay carries between the read that decided the client resumes and
    # the session's own - the same answer a client gets at the doors, reached through them.
    test "cuts the client off when the log says it has to be sent everything again" do
      moved = create("before leaving")
      {tx, seq} = last_place()
      cursor = Cursor.encode(tx, seq, @policy_hash)

      DB.update(Module2, moved.id, %{c: "moved while away"})
      DB.update(Module2, moved.id, %{c: "moved again while away"})

      put_app_env(:sync, gap_limit: 1)

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      test_pid = self()
      read_gap = read_gap_from(cursor)

      {connection, ref} =
        spawn_monitor(fn ->
          Session.start_link(
            client: test_pid,
            page: @page,
            policy_hash: @policy_hash,
            read_gap: read_gap
          )

          Process.sleep(:infinity)
        end)

      assert_receive {:DOWN, ^ref, :process, ^connection, {:full_resync, :gap_too_large}}

      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
      refute_received {:sync_synced, _scope, _cursor}
    end
  end

  # The gap is read once every window has filled, so whatever changed while the client was being
  # caught up is in it. The silent window keeps the client being caught up while the test changes
  # things, and is then filled by hand.
  describe "start_link/1 - coming back while things change" do
    # Reads every frame until the client is told its store is whole, the catch-up's included.
    defp caught_up_deltas(acc \\ []) do
      receive do
        {:sync_deltas, _cursor, deltas, _applied_seq} -> caught_up_deltas(acc ++ deltas)
        {:sync_synced, :page, _cursor} -> caught_up_deltas(acc)
        {:sync_synced, :all, _cursor} -> acc
      after
        1_000 -> flunk("the client was never told it was caught up")
      end
    end

    defp cursor_now do
      {tx, seq} = last_place()

      Cursor.encode(tx, seq, @policy_hash)
    end

    defp deltas_for(deltas, row) do
      Enum.filter(deltas, &(&1.id == row.id))
    end

    defp finish_filling(session, window_id) do
      ResultStore.put(window_id, 1, [])
      send(session, {:round, window_id, 1, [], nil})
    end

    defp prefill(window_ids) do
      hold_windows(window_ids)

      Enum.each(window_ids, &Evaluator.round(&1, []))
      wait_until(fn -> Enum.all?(window_ids, &(ResultStore.versions(&1) != [])) end)
    end

    # The board window filled, the other still filling, as a client coming back with a gap naming
    # the given rows, each moved to the given title while it was away.
    defp start_catching_up!(rows) do
      windows(%{@page => [@board_window, @other_window]})
      prefill([@board_window])
      hold_silently(@other_window)

      cursor = cursor_now()

      Enum.each(rows, fn {row, title} -> DB.update(Module2, row.id, %{c: title}) end)

      start_session!(gap_end: last_place(), read_gap: read_gap_from(cursor))
    end

    defp with_revisions(row, revisions) do
      %{row | __meta__: %{row.__meta__ | revisions: revisions}}
    end

    test "tells a returning client about a row renamed while it was being caught up" do
      moved = create("before leaving")
      renamed = create("old title")
      session = start_catching_up!([{moved, "moved while away"}])

      DB.update(Module2, renamed.id, %{c: "new title"})
      Evaluator.round(@board_window, transactions(renamed.id, ["c"]))
      settle([@board_window], session)

      finish_filling(session, @other_window)

      assert [%{data: data, op: :put_entity}] = deltas_for(caught_up_deltas(), renamed)
      assert data.c == "new title"
    end

    test "hands over a row created while the client was being caught up" do
      moved = create("before leaving")
      session = start_catching_up!([{moved, "moved while away"}])

      created = create("created while catching up")
      Evaluator.round(@board_window, [])
      settle([@board_window], session)

      finish_filling(session, @other_window)

      assert [%{data: data, op: :put_entity}] = deltas_for(caught_up_deltas(), created)
      assert data.c == "created while catching up"
    end

    test "tells a returning client to drop a row deleted while it was being caught up" do
      moved = create("before leaving")
      deleted = create("deleted while catching up")
      session = start_catching_up!([{moved, "moved while away"}])

      DB.delete(Module2, deleted.id)
      Evaluator.round(@board_window, [])
      settle([@board_window], session)

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), deleted) == [
               %{
                 id: deleted.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    # The window's first round still held the row, and the gap names it - told from that round,
    # the client would be handed back a row that no longer exists.
    test "drops a row the gap names once it is deleted while the client is being caught up" do
      moved = create("before leaving")
      session = start_catching_up!([{moved, "moved while away"}])

      DB.delete(Module2, moved.id)
      Evaluator.round(@board_window, [])
      settle([@board_window], session)

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), moved) == [
               %{id: moved.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Entity.Module2"}
             ]
    end

    test "tells a row the gap names once, as it stands after it changed again" do
      moved = create("before leaving")
      session = start_catching_up!([{moved, "moved while away"}])

      DB.update(Module2, moved.id, %{c: "moved again while catching up"})
      Evaluator.round(@board_window, transactions(moved.id, ["c"]))
      settle([@board_window], session)

      finish_filling(session, @other_window)

      assert [%{data: data, op: :put_entity}] = deltas_for(caught_up_deltas(), moved)
      assert data.c == "moved again while catching up"
    end

    # The change reached the running evaluator before the session took the window up, so the round
    # the session reads already holds it and no round of its own will ever name it.
    test "tells a change a running window took in before the session began" do
      moved = create("before leaving")
      renamed = create("old title")
      windows(%{@page => [@board_window]})
      prefill([@board_window])

      cursor = cursor_now()
      DB.update(Module2, moved.id, %{c: "moved while away"})
      gap_end = last_place()

      DB.update(Module2, renamed.id, %{c: "new title"})
      Evaluator.round(@board_window, transactions(renamed.id, ["c"]))
      wait_until(fn -> ResultStore.versions(@board_window) == [2, 1] end)

      start_session!(gap_end: gap_end, read_gap: read_gap_from(cursor))

      assert [%{data: data, op: :put_entity}] = deltas_for(caught_up_deltas(), renamed)
      assert data.c == "new title"
    end

    # A window still starting its evaluator fills after the delete, so it never held the row and
    # no round of its own can say it went.
    test "drops a row deleted before a window still filling took it in" do
      kept = create("kept")
      deleted = create("deleted while catching up")
      windows(%{@page => [@board_window]})
      hold_silently(@board_window)

      session = start_session!(gap_end: nil, read_gap: read_gap_from(cursor_now()))

      DB.delete(Module2, deleted.id)

      ResultStore.put(@board_window, 1, [kept])
      send(session, {:round, @board_window, 1, [], nil})

      assert caught_up_deltas() == [
               %{
                 id: deleted.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "drops what a related row hid while the client was being caught up" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      parent =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      child =
        %{parent_id: parent.id}
        |> PolicyModule5.new()
        |> DB.create!()

      windows(%{@page => [@reach_window, @board_window]})
      prefill([@reach_window])
      hold_silently(@board_window)

      session =
        start_session!(
          actor_user_id: user.id,
          edges: Edges.derive([PolicyModule5]),
          gap_end: nil,
          read_gap: read_gap_from(cursor_now(), user.id)
        )

      DB.update(PolicyModule1, parent.id, %{public: false})
      Evaluator.round(@reach_window, [])
      settle([@reach_window], session)

      finish_filling(session, @board_window)

      assert deltas_for(caught_up_deltas(), child) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module5"}
             ]
    end

    test "drops what a grant revoked while the client was being caught up covered" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      gated = DB.create!(PolicyModule1.new())
      Auth.grant_role(user, :viewer, gated)

      windows(%{@page => [@other_window, @board_window]})
      prefill([@other_window])
      hold_silently(@board_window)

      session =
        start_session!(
          actor_user_id: user.id,
          gap_end: nil,
          read_gap: read_gap_from(cursor_now(), user.id)
        )

      Auth.revoke_role(user, :viewer, gated)
      Evaluator.round(@other_window, [])
      settle([@other_window], session)

      finish_filling(session, @board_window)

      assert deltas_for(caught_up_deltas(), gated) == [
               %{id: gated.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # The change lands just after the gap was read, so the gap doesn't name it and the window's
    # round for it reaches the session once the client is caught up.
    test "tells a change committed just after the gap was read once the client is caught up" do
      renamed = create("old title")
      windows(%{@page => [@board_window]})
      prefill([@board_window])

      test_pid = self()
      read_from_cursor = read_gap_from(cursor_now())

      # Holds the session between reading the gap and judging it, for the change to land there.
      read_gap = fn ->
        gap = read_from_cursor.()

        send(test_pid, {:gap_read, self()})

        receive do
          :judge -> gap
        end
      end

      start_session!(gap_end: nil, read_gap: read_gap)
      assert_receive {:gap_read, session}

      DB.update(Module2, renamed.id, %{c: "new title"})
      Evaluator.round(@board_window, transactions(renamed.id, ["c"]))
      wait_until(fn -> hd(ResultStore.versions(@board_window)) == 2 end)

      send(session, :judge)

      assert_receive {:sync_synced, :all, _cursor}
      assert_receive {:sync_deltas, _cursor, [%{data: patch, id: id, op: :patch_entity}], _seq}
      assert id == renamed.id
      assert patch.c == "new title"
    end

    # A write of two columns under an older stamp leaves the row's highest revision where it was,
    # so the revisions can't say which copy is newer - the moment each window was read can. The
    # newer copy sits in the window between the other two by id, so neither the first nor the last
    # window judged by id holds it.
    test "tells a row three windows hold as the window read last has it" do
      row = create("before leaving")
      windows(%{@page => [@board_window, @other_window, @reach_window]})
      Enum.each([@board_window, @other_window, @reach_window], &hold_silently/1)

      session = start_session!(gap: [gap_effect(row.id)])

      older = with_revisions(%{row | c: "older"}, %{a: 10, b: 100, c: 10})
      newer = with_revisions(%{row | a: false, c: "newer"}, %{a: 20, b: 100, c: 20})

      ResultStore.put(@board_window, 1, [older], 1)
      ResultStore.put(@other_window, 1, [newer], 3)
      ResultStore.put(@reach_window, 1, [older], 2)

      Enum.each([@board_window, @other_window, @reach_window], fn window_id ->
        send(session, {:round, window_id, 1, [], nil})
      end)

      assert_receive {:sync_deltas, _cursor, [%{data: data, op: :put_entity}], _applied_seq}
      assert {data.a, data.c} == {false, "newer"}
    end

    # The row went private between the two windows' reads, so the window read later carries it
    # hidden from this client - which outdates the copy the earlier window let it see.
    test "drops a row the gap names once a window read later hides it" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      named = %{gap_effect(row.id) | type: PolicyModule1}

      session = start_session!(actor_user_id: user.id, gap: [named])

      ResultStore.put(@board_window, 1, [row], 1)
      ResultStore.put(@other_window, 1, [%{row | public: false}], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{id: row.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # The window read later carries the row only under another row - still a copy of it, read
    # later, and hidden from this client.
    test "drops a row the gap names once a window read later carries it hidden under another" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [%{gap_effect(row.id) | type: PolicyModule1}])

      ResultStore.put(@board_window, 1, [row], 1)
      ResultStore.put(@other_window, 1, [%{parent | children: [%{row | public: false}]}], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{id: row.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # The other way round: the row went public between the two reads, so the window read later
    # outdates the hidden copy.
    test "hands over a row the gap names once a window read later shows it" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      named = %{gap_effect(row.id) | type: PolicyModule1}

      session = start_session!(actor_user_id: user.id, gap: [named])

      ResultStore.put(@board_window, 1, [%{row | public: false}], 1)
      ResultStore.put(@other_window, 1, [row], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [Frame.put_entity(row, Frame.row_verdicts(user.id, row))]
    end

    # The child went private between the two reads, so the parent kept from the earlier window
    # can't go on listing it.
    test "takes a row a window read later hides out of the lists of the rows handed over" do
      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      gap = [
        %{gap_effect(parent.id, {200, 1}) | type: PolicyParent},
        %{gap_effect(child.id, {200, 2}) | type: PolicyModule1}
      ]

      session = start_session!(gap: gap)

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}], 1)
      ResultStore.put(@other_window, 1, [%{child | public: false}], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      listing_nothing = %{parent | children: []}

      assert Enum.filter(deltas, &(&1.id == parent.id)) == [
               Frame.put_entity(listing_nothing, Frame.row_verdicts(nil, listing_nothing))
             ]

      assert Enum.filter(deltas, &(&1.id == child.id)) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # A related row moving makes the child appear in the earlier window, but the window read later
    # has the child under another parent the client can't see through.
    test "hands over nothing a related row revealed once a window read later hides it" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      public_parent =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      private_parent = DB.create!(PolicyModule1.new())

      child =
        %{parent_id: public_parent.id}
        |> PolicyModule5.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @reach_window]})
      hold_silently(@board_window)
      hold_silently(@reach_window)

      session =
        start_session!(
          actor_user_id: user.id,
          edges: Edges.derive([PolicyModule5]),
          gap: [related_effect(public_parent.id, PolicyModule1, %{"public" => 1})]
        )

      ResultStore.put(@reach_window, 1, [child], 1)
      ResultStore.put(@board_window, 1, [%{child | parent_id: private_parent.id}], 2)
      send(session, {:round, @reach_window, 1, [], nil})
      send(session, {:round, @board_window, 1, [], nil})

      assert deltas_for(caught_up_deltas(), child) == []
    end

    # A grant taken away while the client was gone hides the row in the earlier window, but the
    # window read later has it public, so the client keeps it.
    test "takes nothing away that a window read later shows" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      row = DB.create!(PolicyModule1.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session =
        start_session!(
          actor_user_id: user.id,
          gap: [gap_effect(Entity.generate_id())],
          grants_then: [viewer_grant(user.id, row)]
        )

      ResultStore.put(@board_window, 1, [row], 1)
      ResultStore.put(@other_window, 1, [%{row | public: true}], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert deltas_for(caught_up_deltas(), row) == []
    end

    # Both windows hold the row; the board window's round for the change was read while the client
    # was catching up, the other window's is still on its way. Its copy is the older one.
    test "tells a row two windows hold as the window that took in its change has it" do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        windows: %{
          @board_window => Stage.normalize(Module2),
          @other_window => other_window_term(),
          @reach_window => Stage.normalize(PolicyModule5)
        }
      })

      moved = create("before leaving")
      windows(%{@page => [@board_window, @other_window, @reach_window]})
      prefill([@board_window, @other_window])
      hold_silently(@reach_window)

      session = start_session!(gap_end: nil, read_gap: read_gap_from(cursor_now()))

      DB.update(Module2, moved.id, %{a: false, c: "moved while catching up"})
      Evaluator.round(@board_window, transactions(moved.id, ["a", "c"]))
      settle([@board_window], session)

      finish_filling(session, @reach_window)

      assert [%{data: data, op: :put_entity}] = deltas_for(caught_up_deltas(), moved)
      assert data.c == "moved while catching up"
    end

    # The window starts its evaluator after the related row moved, so its first round already has
    # the child hidden, and the session never held it there to see it go.
    test "drops what a related row hid before a window still filling took it in" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      parent =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      child =
        %{parent_id: parent.id}
        |> PolicyModule5.new()
        |> DB.create!()

      windows(%{@page => [@reach_window]})
      hold_silently(@reach_window)

      session =
        start_session!(
          actor_user_id: user.id,
          edges: Edges.derive([PolicyModule5]),
          gap_end: nil,
          read_gap: read_gap_from(cursor_now(), user.id)
        )

      DB.update(PolicyModule1, parent.id, %{public: false})

      # What the window's evaluator would read once it starts.
      rows =
        PolicyModule5
        |> Stage.normalize()
        |> QueryRunner.run(DB.mapping())

      ResultStore.put(@reach_window, 1, rows)
      send(session, {:round, @reach_window, 1, [], nil})

      assert deltas_for(caught_up_deltas(), child) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module5"}
             ]
    end

    # Read when the session began, the gap would miss what changed while the windows filled.
    test "reads the gap only once every window has filled" do
      windows(%{@page => [@board_window, @other_window]})
      prefill([@board_window])
      hold_silently(@other_window)

      test_pid = self()

      session =
        start_session!(
          gap_end: nil,
          read_gap: fn ->
            send(test_pid, :gap_read)

            {:ok, [], nil}
          end
        )

      settle([@board_window], session)
      refute_received :gap_read

      finish_filling(session, @other_window)

      assert_receive :gap_read
    end

    # The board window's last round left the ring while the other window was still filling, so the
    # gap has nothing left to be judged against.
    test "cuts the client off when a window's last round left the ring before the gap was read" do
      windows(%{@page => [@board_window, @other_window]})
      prefill([@board_window])
      hold_silently(@other_window)

      session = start_session!(gap_end: nil, read_gap: fn -> {:ok, [], nil} end)
      settle([@board_window], session)

      Enum.each(2..4, &ResultStore.put(@board_window, &1, []))

      ref = Process.monitor(session)
      finish_filling(session, @other_window)

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
      refute_received {:sync_synced, _scope, _cursor}
    end
  end

  # A grant given or taken away while a client was gone moves ONE row and changes what it may see
  # of many, which the gap names none of. So the rows are judged twice - under the grants it held
  # then and the ones it holds now - and the difference is told after the gap's own batches.
  describe "start_link/1 - coming back to changed grants" do
    setup do
      user =
        %{email: "resumed@example.com"}
        |> Module14.new()
        |> DB.create!()

      %{user: user}
    end

    defp viewer_grant(user_id, row) do
      %RoleGrant{
        user_id: user_id,
        entity_type: PolicyModule1,
        entity_id: row.id,
        role: :viewer
      }
    end

    defp gated_row do
      DB.create!(PolicyModule1.new())
    end

    test "tells a returning client to drop what a revoked grant covered", %{user: user} do
      revoked = gated_row()
      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(
        actor_user_id: user.id,
        gap: [gap_effect(Entity.generate_id())],
        grants_then: [viewer_grant(user.id, revoked)]
      )

      assert_receive {:sync_deltas, _cursor, gap_deltas, _applied_seq}
      assert [%{op: :unsync_entity}] = gap_deltas

      assert_receive {:sync_deltas, _cursor, shift_deltas, _applied_seq}

      assert shift_deltas == [
               %{
                 id: revoked.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Policy.Module1"
               }
             ]
    end

    test "hands over what a grant given while away covers", %{user: user} do
      granted = gated_row()
      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      Auth.grant_role(user, :viewer, granted)

      start_session!(
        actor_user_id: user.id,
        gap: [gap_effect(Entity.generate_id())],
        grants_then: []
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, shift_deltas, _applied_seq}

      assert [%{data: data, id: id, op: :put_entity}] = shift_deltas
      assert id == granted.id
      assert data.public == false
    end

    # The replay has already spoken of a row the gap named, so the shift leaves it alone - saying
    # it twice would have the client answer a question it was given the answer to.
    test "says nothing twice about a row the gap already named", %{user: user} do
      revoked = gated_row()
      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(
        actor_user_id: user.id,
        gap: [gap_effect(revoked.id)],
        grants_then: [viewer_grant(user.id, revoked)]
      )

      assert_receive {:sync_deltas, _cursor, gap_deltas, _applied_seq}
      assert [%{id: named_id, op: :unsync_entity}] = gap_deltas
      assert named_id == revoked.id

      refute_receive {:sync_deltas, _cursor, _shift_deltas, _applied_seq}, 100
    end

    test "says the pages are answerable only once the shift has been told", %{user: user} do
      revoked = gated_row()
      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(
        actor_user_id: user.id,
        gap: [gap_effect(Entity.generate_id())],
        grants_then: [viewer_grant(user.id, revoked)]
      )

      # Received in this order, so the client never reads its own store while it still holds a
      # row a revoked grant covered.
      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, _shift_deltas, _applied_seq}
      assert_receive {:sync_synced, :page, _cursor}
    end

    test "dates the shift no further than the read that decided the client resumes", %{
      user: user
    } do
      revoked = gated_row()
      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(
        actor_user_id: user.id,
        gap: [
          gap_effect(Entity.generate_id(), {900, 7}),
          gap_effect(Entity.generate_id(), {900, 8})
        ],
        gap_end: {900, 7},
        grants_then: [viewer_grant(user.id, revoked)]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, shift_cursor, shift_deltas, _applied_seq}
      assert [%{id: id, op: :unsync_entity}] = shift_deltas
      assert id == revoked.id
      assert Cursor.decode(shift_cursor) == {:ok, 900, 7, @policy_hash}
    end

    # The shift is judged per window and merged by id: a window with nothing to say about grants
    # must not wipe what another window found. The board window is delivered last and contributes
    # nothing, since its type is readable by everyone whatever grants are held.
    test "keeps what one window found when another has nothing to say", %{user: user} do
      revoked = gated_row()
      create("in the board window")

      # The board window is listed LAST, so it is the one that reports with nothing to say after
      # the other has already found something.
      windows(%{@page => [@other_window, @board_window]})
      hold_windows([@board_window, @other_window])

      start_session!(
        actor_user_id: user.id,
        gap: [gap_effect(Entity.generate_id())],
        grants_then: [viewer_grant(user.id, revoked)]
      )

      # A window's own rounds send nothing while a replay is in flight - they are remembered as
      # the rows the gap named - so the frames are the gap's batch and then the shift's.
      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, shift_deltas, _applied_seq}

      assert [%{id: id, op: :unsync_entity}] = shift_deltas
      assert id == revoked.id
    end

    test "gives a returning client with unchanged grants no second look", %{user: user} do
      gated_row()
      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(actor_user_id: user.id, gap: [gap_effect(Entity.generate_id())])

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      refute_receive {:sync_deltas, _cursor, _shift_deltas, _applied_seq}, 100
    end
  end

  describe "start_link/1 - coming back to a moved related row" do
    setup do
      user =
        %{email: "reached@example.com"}
        |> Module14.new()
        |> DB.create!()

      %{edges: Edges.derive([PolicyModule5]), user: user}
    end

    defp child_of(parent) do
      %{parent_id: parent.id}
      |> PolicyModule5.new()
      |> DB.create!()
    end

    defp public_parent do
      %{public: true}
      |> PolicyModule1.new()
      |> DB.create!()
    end

    defp start_reach_session!(opts) do
      windows(%{@page => [@reach_window]})
      hold_windows([@reach_window])

      start_session!(opts)
    end

    test "drops what a moved related row no longer admits", %{edges: edges, user: user} do
      parent = DB.create!(PolicyModule1.new())
      child = child_of(parent)

      start_reach_session!(
        actor_user_id: user.id,
        edges: edges,
        gap: [related_effect(parent.id, PolicyModule1, %{"public" => 1})]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, reach_deltas, _applied_seq}

      assert reach_deltas == [
               %{
                 id: child.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Policy.Module5"
               }
             ]
    end

    # The session is a state machine over what it is handed, and `start_link/1` documents the
    # index as absent for a first arrival - so a caller naming a gap without one asks for the
    # replay alone rather than for a crash.
    test "gives a returning client handed no dependency index no second look", %{user: user} do
      child_of(public_parent())

      start_reach_session!(
        actor_user_id: user.id,
        gap: [related_effect(Entity.generate_id(), PolicyModule1, %{"public" => 1})]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      refute_receive {:sync_deltas, _cursor, _reach_deltas, _applied_seq}, 100
    end

    test "hands over what a moved related row now admits", %{edges: edges, user: user} do
      parent = public_parent()
      child = child_of(parent)

      start_reach_session!(
        actor_user_id: user.id,
        edges: edges,
        gap: [related_effect(parent.id, PolicyModule1, %{"public" => 1})]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, reach_deltas, _applied_seq}

      assert [%{id: id, op: :put_entity}] = reach_deltas
      assert id == child.id
    end

    test "leaves rows alone when the gap names nothing they lean on", %{edges: edges, user: user} do
      child_of(public_parent())

      start_reach_session!(
        actor_user_id: user.id,
        edges: edges,
        gap: [gap_effect(Entity.generate_id())]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      refute_receive {:sync_deltas, _cursor, _reach_deltas, _applied_seq}, 100
    end

    # The same setup as "drops what a moved related row no longer admits", differing only in which
    # column the gap says moved - so the pair is what binds the narrowing end to end.
    test "leaves rows alone when the named row moved on an attribute the rule does not read", %{
      edges: edges,
      user: user
    } do
      parent = DB.create!(PolicyModule1.new())
      child_of(parent)

      start_reach_session!(
        actor_user_id: user.id,
        edges: edges,
        gap: [related_effect(parent.id, PolicyModule1, %{"priority" => 1})]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      refute_receive {:sync_deltas, _cursor, _reach_deltas, _applied_seq}, 100
    end

    # The replay has already handed the row over, so the reach leaves it alone - the same dedupe a
    # grant change answers to, reached from the other source.
    test "says nothing twice about a row the gap already named", %{edges: edges, user: user} do
      parent = public_parent()
      child = child_of(parent)

      start_reach_session!(
        actor_user_id: user.id,
        edges: edges,
        gap: [
          related_effect(parent.id, PolicyModule1, %{"public" => 1}),
          related_effect(child.id, PolicyModule5, %{"parent_id" => 1})
        ]
      )

      assert_receive {:sync_deltas, _cursor, gap_deltas, _applied_seq}
      assert [%{id: named_id, op: :put_entity}] = Enum.filter(gap_deltas, &(&1.id == child.id))
      assert named_id == child.id

      refute_receive {:sync_deltas, _cursor, _reach_deltas, _applied_seq}, 100
    end

    # The two sources feed ONE accumulator, so a batch carries what the grants decided differently
    # and what a moved related row now decides together. Nothing else covers the pair: the reach
    # tests hold one window each, where merging into a fresh map is indistinguishable from merging
    # into what is already there.
    test "sends what grants and a related row decided in one batch", %{edges: edges, user: user} do
      revoked = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyModule1.new())
      child = child_of(parent)

      windows(%{@page => [@other_window, @reach_window]})
      hold_windows([@other_window, @reach_window])

      start_session!(
        actor_user_id: user.id,
        edges: edges,
        gap: [related_effect(parent.id, PolicyModule1, %{"public" => 1})],
        grants_then: [viewer_grant(user.id, revoked)]
      )

      assert_receive {:sync_deltas, _cursor, _gap_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, shift_deltas, _applied_seq}

      dropped_ids =
        shift_deltas
        |> Enum.filter(&(&1.op == :unsync_entity))
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert dropped_ids == Enum.sort([child.id, revoked.id])
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

      assert_receive {:sync_deltas, nil, first, _applied_seq}
      assert length(first) == 2

      assert_receive {:sync_deltas, nil, second, _applied_seq}
      assert length(second) == 1

      assert_receive {:sync_synced, :all, _cursor}
    end

    # Everything that is not an appeared row rides with the first frame rather than being repeated:
    # a client applying the batches in order sees each of them once.
    test "sends what is not an appeared row once, with the first frame" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, nil, _fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      put_app_env(:sync, rows_per_frame: 2)

      # Three rows appear while the one the client holds changes, so the round splits across two
      # frames and the patch has somewhere it could wrongly be repeated.
      Enum.each(1..3, &create("appeared #{&1}"))
      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), nil)

      assert_receive {:sync_deltas, _first_cursor, first, _applied_seq}
      assert_receive {:sync_deltas, _second_cursor, second, _applied_seq}

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

      assert_receive {:sync_synced, :all, _cursor}

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

      assert_receive {:sync_synced, :page, _cursor}
      refute_receive {:sync_synced, :all, _cursor}, 100
    end

    test "says every page is answerable once the last window has filled" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
      assert_receive {:sync_synced, :all, _cursor}
    end

    test "says a page reading nothing is answerable at once, and waits for the rest" do
      windows(%{@other_page => [@other_window]})
      hold_windows([@other_window])

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
      assert_receive {:sync_synced, :all, _cursor}
    end

    test "says both at once for a build downloading nothing" do
      windows(%{})

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
      assert_receive {:sync_synced, :all, _cursor}
    end

    test "says each scope once, however many windows fill after it" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
      assert_receive {:sync_synced, :all, _cursor}

      Evaluator.round(@board_window, [])
      Evaluator.round(@other_window, [])

      refute_receive {:sync_synced, _scope, _cursor}, 100
    end

    # The marker is what a filled client resumes from: a deltas frame carries no place until the
    # pot is whole, and a client that is filled and then left alone receives no further frame at
    # all - so without this it would hold everything it was sent and have nowhere to come back to.
    test "hands over the place the client may come back from" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0})

      assert_receive {:sync_synced, :all, cursor}
      assert cursor == Cursor.encode(200, 0, @policy_hash)
    end

    # The claim a place makes is "everything up to here is applied", which a client holding one
    # page of several cannot honour.
    test "names no place while only a first arrival's own page is answerable" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window])
      hold_silently(@other_window)

      start_session!(fill_place: {200, 0})

      assert_receive {:sync_synced, :page, cursor}
      assert cursor == nil
    end

    # A client that came back kept what it had and is told only what moved, so it holds a whole
    # pot from its first frame - and its page marker is as honourable a claim as its last.
    test "names a place on the page marker of a client that came back" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0}, gap: [])

      assert_receive {:sync_synced, :page, cursor}
      assert cursor == Cursor.encode(200, 0, @policy_hash)
    end
  end

  describe "start_link/1 - first rows" do
    test "sends the rows the window holds" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

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

      assert_receive {:sync_synced, :page, _cursor}
      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end

    test "sends only the rows this client may read" do
      user =
        %{email: "reader@example.com"}
        |> Module14.new()
        |> DB.create!()

      readable =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      DB.create!(PolicyModule1.new())

      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!(actor_user_id: user.id)

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == readable.id
    end

    test "sends an anonymous visitor the rows anyone may read, and no others" do
      readable =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      DB.create!(PolicyModule1.new())

      windows(%{@page => [@other_window]})
      hold_windows([@other_window])

      start_session!([])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == readable.id
    end

    test "says it is done once every window has sent its rows" do
      create("first")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])

      assert_receive {:sync_deltas, _cursor, _board_deltas, _applied_seq}
      assert_receive {:sync_synced, :page, _cursor}
    end

    test "says it is done immediately for a page reaching no window" do
      windows(%{@page => []})

      start_session!([])

      assert_receive {:sync_synced, :page, _cursor}
    end

    test "reads the round a running evaluator already has rather than asking for another" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      test_pid = self()
      other_client = spawn_link(fn -> forward(test_pid) end)

      start_session!(client: other_client)

      assert_receive {:forwarded, {:sync_deltas, _cursor, deltas, _applied_seq}}
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
      assert_receive {:sync_synced, :all, _cursor}

      [{evaluator, _value}] = Registry.lookup(Evaluator.registry(), @other_window)

      ref = Process.monitor(session)

      # A signal from here reaches the session in order, so once this call answers, the session has
      # taken up the monitor. The kill's way to it goes through the evaluator and could overtake a
      # bare monitor request.
      :sys.get_state(session)

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
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]))

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: patch, id: id, op: :patch_entity}] = deltas
      assert id == task.id
      assert patch.c == "after"
    end

    test "sends a row that entered the window as it stands" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_synced, :page, _cursor}

      task = create("appeared later")
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == task.id
    end

    test "tells the client to drop a row that left the only window holding it" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      DB.delete(Module2, task.id)
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

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
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      Evaluator.round(@board_window, [])

      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end
  end

  # How far this replica's own batches are applied in what a frame carries. The client needs it
  # because a write of its own, arriving back, looks exactly like the write that made it: the
  # values match, so nothing in the row says whether the change is already in or still to come.
  describe "handle :round - the watermark" do
    test "names the number the session was given, before any round of its own" do
      create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(applied_seq: 3, replica_id: @replica_id)

      assert_receive {:sync_deltas, _cursor, _deltas, 3}
    end

    test "raises it to the highest of this replica's batches in the round" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(applied_seq: 3, replica_id: @replica_id)
      assert_receive {:sync_deltas, _cursor, _fill, 3}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"], ref(@replica_id, 9)))

      assert_receive {:sync_deltas, _cursor, _deltas, 9}
    end

    # Another browser's writes say nothing about this one's - and naming them would tell this
    # client which rows that browser is responsible for, which is exactly what one integer about
    # the receiver alone avoids.
    test "passes over another replica's batches" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(applied_seq: 3, replica_id: @replica_id)
      assert_receive {:sync_deltas, _cursor, _fill, 3}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"], ref(@other_replica_id, 9)))

      assert_receive {:sync_deltas, _cursor, _deltas, 3}
    end

    # A round carrying an older batch of this replica's says nothing new about it. Lowering the
    # number would have the client apply writes it had already been told were in.
    test "never lowers it" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(applied_seq: 9, replica_id: @replica_id)
      assert_receive {:sync_deltas, _cursor, _fill, 9}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"], ref(@replica_id, 4)))

      assert_receive {:sync_deltas, _cursor, _deltas, 9}
    end

    # An effect with no batch behind it belongs to nobody - a command's write, a seed's, the
    # framework's own.
    test "passes over an effect no batch wrote" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(applied_seq: 3, replica_id: @replica_id)
      assert_receive {:sync_deltas, _cursor, _fill, 3}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]))

      assert_receive {:sync_deltas, _cursor, _deltas, 3}
    end

    test "names no number for a session serving no replica" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _fill, nil}

      DB.update(Module2, task.id, %{c: "after"})
      Evaluator.round(@board_window, transactions(task.id, ["c"], ref(@replica_id, 9)))

      assert_receive {:sync_deltas, _cursor, _deltas, nil}
    end
  end

  describe "handle :round - the place a frame claims" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        windows: %{
          @board_window => Stage.normalize(Module2),
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

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert cursor == nil
    end

    test "claims the place its windows were taken up at once the pot is whole" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0})

      # The fill's own frame carries no place and has to be taken out of the way first.
      assert_receive {:sync_deltas, nil, _fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), nil)

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 200, 0, @policy_hash}
    end

    # A returning client kept what it had, so it can date its store from the first frame - there is
    # no half-filled state for it to misreport. What it is dated BY is the last effect in the batch
    # rather than the fill place, which is what lets a replay be picked up where it stopped.
    test "dates each replayed batch by the last effect in it" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0}, gap: [gap_effect(moved.id, {900, 7})])

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 7, @policy_hash}
    end

    # The session's own read can reach further than the one that decided the client resumes, and
    # the rounds behind those effects may not have reached it yet - so a batch vouches for no more
    # than that first read found.
    test "dates a replayed batch no further than the read that decided the client resumes" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(
        fill_place: {200, 0},
        gap: [gap_effect(moved.id, {900, 7}), gap_effect(Entity.generate_id(), {900, 8})],
        gap_end: {900, 7}
      )

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 7, @policy_hash}
    end

    test "dates no replayed batch when the read that decided the client resumes found nothing" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0}, gap: [gap_effect(moved.id, {900, 7})], gap_end: nil)

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert cursor == nil
    end

    # The rules the session judged its rows by, not whatever rules are current when a frame goes
    # out: a place vouches for what the client holds there.
    test "dates its places under the rules it was started with" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      other_policy_hash = "fedcba9876543210fedcba9876543210"

      start_session!(
        fill_place: {200, 0},
        gap: [gap_effect(moved.id, {900, 7})],
        policy_hash: other_policy_hash
      )

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 7, other_policy_hash}
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

      assert_receive {:sync_deltas, nil, _fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {900, 7})

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 7, @policy_hash}
    end

    test "claims the place of the window furthest behind, not the one furthest ahead" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_deltas, _board_cursor, _board_deltas, _applied_seq}
      assert_receive {:sync_deltas, _other_cursor, _other_deltas, _applied_seq}

      # Only the board window advances. The other window is still back at the fill place, and a
      # frame claiming the board's place would tell the client it is caught up past changes the
      # other window has not delivered.
      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {900, 0})

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 200, 0, @policy_hash}
    end

    test "claims the newer place once every window has caught up to it" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_deltas, _board_cursor, _board_deltas, _applied_seq}
      assert_receive {:sync_deltas, _other_cursor, _other_deltas, _applied_seq}

      Evaluator.round(@other_window, [], {900, 0})

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {900, 0})

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 0, @policy_hash}
    end

    # A round arriving out of order must not walk a window's place backwards: both places it could
    # claim are sound, so the further one is kept.
    test "keeps a window's place at the furthest a round has claimed for it" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_deltas, _first_cursor, _first_deltas, _applied_seq}

      Evaluator.round(@board_window, [], {900, 0})

      DB.update(Module2, task.id, %{c: "moved"})
      Evaluator.round(@board_window, transactions(task.id, ["c"]), {500, 0})

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 0, @policy_hash}
    end
  end

  describe "handle :round - past the ring" do
    test "ends when told about a round the store no longer reaches" do
      create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      session = start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      ref = Process.monitor(session)

      # A version the ring dropped before this session got to it.
      send(session, {:round, @board_window, 999, [], nil})

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
    end

    # The dropped round already moved its window's place past itself, so a frame telling the other
    # window's round would claim a place past a change the client never got.
    test "tells nothing of another window's round queued ahead of the cut" do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        windows: %{
          @board_window => Stage.normalize(Module2),
          @other_window => other_window_term()
        }
      })

      task = create("first")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      session = start_session!(fill_place: {200, 0})
      assert_receive {:sync_synced, :all, _cursor}
      flush_messages()

      ref = Process.monitor(session)
      :sys.suspend(session)

      # A version the ring dropped before this session got to it, carrying a change.
      send(session, {:round, @board_window, 999, transactions(task.id, ["c"]), {250, 0}})

      DB.update(Module2, task.id, %{c: "renamed"})
      Evaluator.round(@other_window, transactions(task.id, ["c"]), {300, 0})
      wait_until(fn -> Process.info(session, :message_queue_len) == {:message_queue_len, 2} end)

      :sys.resume(session)

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end

    # The window's next round is still in the store, so read it would tell only its own changes and
    # claim its own place - past the one the ring dropped.
    test "tells nothing of the same window's next round queued ahead of the cut" do
      task = create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      session = start_session!(fill_place: {200, 0})
      assert_receive {:sync_synced, :all, _cursor}
      flush_messages()

      DB.update(Module2, task.id, %{c: "renamed"})

      rows =
        Module2
        |> Stage.normalize()
        |> QueryRunner.run(DB.mapping())

      # The ring keeps the last three, so version 3 is gone and version 4 is still there.
      Enum.each(2..6, &ResultStore.put(@board_window, &1, rows))

      ref = Process.monitor(session)
      :sys.suspend(session)

      send(session, {:round, @board_window, 3, transactions(task.id, ["c"]), {250, 0}})
      send(session, {:round, @board_window, 4, transactions(task.id, ["c"]), {260, 0}})

      :sys.resume(session)

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end

    test "takes the connection with it, so the client comes back through the doors" do
      create("first")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      test_pid = self()

      connection =
        spawn(fn ->
          {:ok, session} =
            Session.start_link(client: test_pid, page: @page, policy_hash: @policy_hash)

          send(test_pid, {:connected, session})

          Process.sleep(:infinity)
        end)

      assert_receive {:connected, session}
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      ref = Process.monitor(connection)
      send(session, {:round, @board_window, 999, [], nil})

      assert_receive {:DOWN, ^ref, :process, ^connection, :behind_the_ring}
    end
  end

  describe "handle :round - the pot" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        windows: %{
          @board_window => Stage.normalize(Module2),
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
      assert_receive {:sync_deltas, _cursor, _board_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, _other_deltas, _applied_seq}

      # The row leaves one window without leaving the database, so the other still carries it -
      # and a client that keeps the row has been told nothing, which is no frame at all.
      DB.update(Module2, task.id, %{a: false})
      Evaluator.round(@other_window, transactions(task.id, ["a"]))

      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end

    test "drops a row once it has left every window holding it" do
      task = create("in both windows")
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _board_deltas, _applied_seq}
      assert_receive {:sync_deltas, _cursor, _other_deltas, _applied_seq}

      DB.delete(Module2, task.id)

      # Gone from one window, still held through the other - nothing to tell the client yet.
      Evaluator.round(@other_window, [])
      refute_receive {:sync_deltas, _cursor, _other_deltas, _applied_seq}, 100

      # Gone from the last window holding it, so now it leaves the client too.
      Evaluator.round(@board_window, [])
      assert_receive {:sync_deltas, _cursor, board_deltas, _applied_seq}
      assert [%{id: unsynced_id, op: :unsync_entity}] = board_deltas
      assert unsynced_id == task.id
    end
  end

  describe "handle :round - the pot over reach" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        windows: %{
          @bare_label_window => Stage.normalize(Module29),
          @board_window => Stage.normalize(Module2),
          @include_window => include_window_term(),
          @inverse_window => inverse_window_term(),
          @label_window => label_window_term(),
          @message_window => Stage.normalize(Module28)
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
      assert_receive {:sync_deltas, _board_cursor, _board_fill, _applied_seq}
      assert_receive {:sync_deltas, _include_cursor, _include_fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      # The child leaves the include window's reach without leaving the database - the board
      # window still roots it, so the client keeps the row and is told nothing.
      source
      |> delete_relationship(:a, child.id)
      |> DB.update()

      Evaluator.round(@include_window, [])

      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end

    test "drops a child once it has left every reach holding it" do
      child = create("held two ways")
      source = include_source(child)
      windows(%{@page => [@board_window, @include_window]})
      hold_windows([@board_window, @include_window])

      start_session!([])
      assert_receive {:sync_deltas, _board_cursor, _board_fill, _applied_seq}
      assert_receive {:sync_deltas, _include_cursor, _include_fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      source
      |> delete_relationship(:a, child.id)
      |> DB.update()

      Evaluator.round(@include_window, [])
      refute_receive {:sync_deltas, _cursor, _include_deltas, _applied_seq}, 100

      DB.delete(Module2, child.id)
      Evaluator.round(@board_window, [])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{id: unsynced_id, op: :unsync_entity}] = deltas
      assert unsynced_id == child.id
    end

    test "names a dropped child by its own type, not the window's root type" do
      child = create("reached only through the include")
      source = include_source(child)
      windows(%{@page => [@include_window]})
      hold_windows([@include_window])

      start_session!([])
      assert_receive {:sync_deltas, _fill_cursor, _fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      source
      |> delete_relationship(:a, child.id)
      |> DB.update()

      Evaluator.round(@include_window, [])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{
                 id: child.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "drops a row reached only through an inverse once it moves out of the reach" do
      general =
        %{name: "general"}
        |> Module26.new()
        |> DB.create!()

      random =
        %{name: "random"}
        |> Module26.new()
        |> DB.create!()

      message =
        %{body: "hi", channel_id: general.id, position: 1}
        |> Module28.new()
        |> DB.create!()

      windows(%{@page => [@inverse_window]})
      hold_windows([@inverse_window])

      start_session!([])
      assert_receive {:sync_deltas, _fill_cursor, fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      assert Enum.any?(fill, &(&1.op == :put_entity and &1.id == message.id))

      # The message moves to a channel the window does not hold - out of the window's reach, but
      # still in the database.
      DB.update(Module28, message.id, %{channel_id: random.id})

      Evaluator.round(@inverse_window, [])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{
                 id: message.id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module28"
               }
             ]
    end

    # The message stays with the client through the message window, so nothing re-puts it - the
    # label's own set is what tells the client the edge is gone.
    test "tells a client holding a row through another window that it left an inverse" do
      %{label: label, message: message} = labelled_message()
      windows(%{@page => [@label_window, @message_window]})
      hold_windows([@label_window, @message_window])

      start_session!([])
      assert_receive {:sync_deltas, _label_cursor, _label_fill, _applied_seq}
      assert_receive {:sync_deltas, _message_cursor, _message_fill, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      message
      |> delete_relationship(:labels, label.id)
      |> DB.update()

      edge = %{
        data: %{"relationship" => "labels", "target_id" => label.id},
        entity_id: message.id,
        mutation_ref: nil,
        op: :del_relationship,
        type: Module28
      }

      Evaluator.round(@label_window, [{200, [edge]}])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{
                 data: %{relationship: "messages", target_id: message.id},
                 id: label.id,
                 op: :del_relationship,
                 type: "Hologram.Test.Fixtures.Entity.Module29"
               }
             ]
    end

    test "replays a gap holding an edge by handing over its target" do
      assert_replayed_with_set([@label_window])
    end

    # A copy of the label without its messages, arriving after the one holding them, never stands
    # for it - nor the other way round.
    test "replays an edge's target with its set while another window holds it bare" do
      assert_replayed_with_set([@label_window, @bare_label_window])
    end

    test "replays an edge's target with its set while another window listed first holds it bare" do
      assert_replayed_with_set([@bare_label_window, @label_window])
    end

    test "replays a gap touching a row held only through reach" do
      child = create("moved while away")
      include_source(child)
      windows(%{@page => [@include_window]})
      hold_windows([@include_window])

      start_session!(gap: [gap_effect(child.id)])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == child.id
    end
  end

  describe "handle :round - verdicts" do
    setup :verdict_rows

    # The pair moves no value of the project, but the set its archive rule reads.
    test "sends the verdicts a round moved on a held row in a patch naming no value", %{
      locked: locked,
      project: project
    } do
      windows(%{@page => [@project_window]})
      hold_windows([@project_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)
      Evaluator.round(@project_window, label_pair_transactions(project, locked))

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, false)]
    end

    # The label the project holds moves, which no value of the project does.
    test "sends the verdicts a round moved through a related row", %{project: project} do
      loose = verdict_label("loose")
      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, loose.id)

      windows(%{@page => [@project_window]})
      hold_windows([@project_window])

      start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      DB.update!(PolicyLabel, loose.id, name: "locked")
      Evaluator.round(@project_window, label_patch_transactions(loose))

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, false)]
    end

    test "sends nothing when a round moves what a held row's verdicts read and not the verdicts",
         %{project: project} do
      loose = verdict_label("loose")
      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, loose.id)

      windows(%{@page => [@project_window]})
      hold_windows([@project_window])

      session = start_session!([])
      assert_receive {:sync_deltas, _cursor, _first_deltas, _applied_seq}

      DB.update!(PolicyLabel, loose.id, name: "free")
      Evaluator.round(@project_window, label_patch_transactions(loose))
      settle([@project_window], session)

      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end

    # The verdicts are the row's, whichever window holds it.
    test "sends the verdicts a round moved on a row two windows hold once", %{
      locked: locked,
      project: project
    } do
      window_ids = [@project_window, @public_project_window]
      windows(%{@page => window_ids})
      hold_windows(window_ids)

      session = start_session!([])
      assert_receive {:sync_synced, :all, _cursor}
      flush_messages()

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)
      transactions = label_pair_transactions(project, locked)
      Enum.each(window_ids, &Evaluator.round(&1, transactions))
      settle(window_ids, session)

      assert_received {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, false)]
      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end
  end

  describe "start_link/1 - coming back to verdicts" do
    setup :verdict_rows

    # The client may hold verdicts from before this session, under keys a deploy changed since.
    test "tells a returning client the verdicts of a row the gap never named", %{
      project: project
    } do
      windows(%{@page => [@project_window]})
      hold_windows([@project_window])

      gone_id = Entity.generate_id()

      start_session!(gap: [gap_effect(gone_id)])

      assert_receive {:sync_deltas, _cursor, gap_deltas, _applied_seq}

      assert gap_deltas == [
               %{id: gone_id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Entity.Module2"}
             ]

      assert_receive {:sync_deltas, _cursor, verdict_deltas, _applied_seq}
      assert verdict_deltas == [verdicts_patch(project, true)]
    end

    # The silent window keeps the client being caught up while the public window loses the project,
    # which the other window still holds.
    test "tells a returning client the verdicts of a row one window lost while another holds it",
         %{
           project: project
         } do
      window_ids = [@public_project_window, @project_window]
      windows(%{@page => [@public_project_window, @project_window, @other_window]})
      hold_windows(window_ids)

      Enum.each(window_ids, &Evaluator.round(&1, []))
      wait_until(fn -> Enum.all?(window_ids, &(ResultStore.versions(&1) != [])) end)

      hold_silently(@other_window)

      session = start_session!(gap: [])

      DB.update(PolicyProject, project.id, %{public: false})
      Evaluator.round(@public_project_window, project_patch_transactions(project))
      settle([@public_project_window], session)

      ResultStore.put(@other_window, 1, [])
      send(session, {:round, @other_window, 1, [], nil})

      assert_receive {:sync_deltas, nil, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, true)]
    end

    # The project went private between the two windows' reads, so the client may no longer hold it
    # and has no verdicts of it to be told.
    test "tells no verdicts of a row a window read later hides", %{project: project} do
      windows(%{@page => [@project_window, @public_project_window]})
      hold_silently(@project_window)
      hold_silently(@public_project_window)

      session = start_session!(gap: [])

      ResultStore.put(@project_window, 1, [project], 1)
      ResultStore.put(@public_project_window, 1, [%{project | public: false}], 2)
      send(session, {:round, @project_window, 1, [], nil})
      send(session, {:round, @public_project_window, 1, [], nil})

      assert_receive {:sync_synced, :all, _cursor}
      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end

    test "tells a returning client that missed nothing the verdicts of the rows it holds", %{
      project: project
    } do
      windows(%{@page => [@project_window]})
      hold_windows([@project_window])

      start_session!(gap: [])

      assert_receive {:sync_deltas, nil, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, true)]
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

  # Drops what the session sent so far, so a test reads only what follows.
  defp flush_messages do
    receive do
      _message -> flush_messages()
    after
      0 -> :ok
    end
  end

  defp forward(test_pid) do
    receive do
      message ->
        send(test_pid, {:forwarded, message})

        forward(test_pid)
    end
  end

  defp assert_replayed_with_set(window_ids) do
    %{label: label, message: message} = labelled_message()
    windows(%{@page => window_ids})
    hold_windows(window_ids)

    # Every window answers before the session subscribes, so it delivers them in the page's order
    # rather than in whichever order their first rounds finish.
    Enum.each(window_ids, &Evaluator.round(&1, []))
    wait_until(fn -> Enum.all?(window_ids, &(ResultStore.versions(&1) != [])) end)

    edge =
      message.id
      |> gap_effect()
      |> Map.merge(%{
        data: %{"relationship" => "labels", "target_id" => label.id},
        op: :add_relationship,
        type: Module28
      })

    start_session!(gap: [edge])

    assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
    assert [%{data: data, op: :put_entity}] = Enum.filter(deltas, &(&1.id == label.id))
    assert data.messages == [message.id]
  end

  # A row of the include window's reach without being any window's root - what the child of the
  # reach tests is held through.
  defp include_source(child) do
    required = DB.create!(Module1.new())

    source =
      %{c_id: required.id}
      |> Module3.new()
      |> DB.create!()

    source
    |> add_relationship(:a, child.id)
    |> DB.update()

    source
  end

  defp include_window_term do
    Module3
    |> Query.include(a)
    |> Stage.normalize()
  end

  defp inverse_window_term do
    Module26
    |> Query.filter(name: "general")
    |> Query.include(messages)
    |> Stage.normalize()
  end

  defp label_pair_transactions(project, label) do
    [
      {200,
       [
         %{
           data: %{"relationship" => "labels", "target_id" => label.id},
           entity_id: project.id,
           mutation_ref: nil,
           op: :add_relationship,
           type: PolicyProject
         }
       ]}
    ]
  end

  defp label_patch_transactions(label) do
    [
      {200,
       [
         %{
           data: %{"name" => "whatever the log said"},
           entity_id: label.id,
           mutation_ref: nil,
           op: :patch_entity,
           type: PolicyLabel
         }
       ]}
    ]
  end

  defp label_window_term do
    Module29
    |> Query.include(messages)
    |> Stage.normalize()
  end

  defp labelled_message do
    label =
      %{name: "urgent"}
      |> Module29.new()
      |> DB.create!()

    message =
      %{body: "tagged", position: 1}
      |> Module28.new()
      |> DB.create!()

    message
    |> add_relationship(:labels, label.id)
    |> DB.update()

    %{label: label, message: message}
  end

  defp other_window_term do
    Module2
    |> Query.filter(a: true)
    |> Stage.normalize()
  end

  # The project's archive rule asks that none of its labels is locked - true until one is.
  defp project_patch_transactions(project) do
    [
      {200,
       [
         %{
           data: %{"public" => "whatever the log said"},
           entity_id: project.id,
           mutation_ref: nil,
           op: :patch_entity,
           type: PolicyProject
         }
       ]}
    ]
  end

  defp project_verdicts(archivable?) do
    Map.new([:archive, :feature, :publish], fn operation ->
      [%{predicates: [clause]}] = Policy.build(PolicyProject)[operation]

      {Policy.verdict_key(PolicyProject, operation, clause), operation != :archive or archivable?}
    end)
  end

  # Waits until each given window's evaluator has handled what it was sent, and the session what
  # they sent it - so a test can say nothing came, rather than that nothing came yet.
  defp settle(window_ids, session) do
    Enum.each(window_ids, fn window_id ->
      [{evaluator, _value}] = Registry.lookup(Evaluator.registry(), window_id)

      :sys.get_state(evaluator)
    end)

    :sys.get_state(session)

    :ok
  end

  defp transactions(entity_id, names, mutation_ref \\ nil) do
    data = Map.new(names, &{&1, "whatever the log said"})

    [
      {200,
       [
         %{
           data: data,
           entity_id: entity_id,
           mutation_ref: mutation_ref,
           op: :patch_entity,
           type: Module2
         }
       ]}
    ]
  end

  # The batch a write belonged to, as the log spells it - string keys, since it comes back out of
  # a jsonb column.
  defp ref(replica_id, seq) do
    %{"replica_id" => replica_id, "seq" => seq}
  end

  defp verdict_label(name) do
    %{name: name}
    |> PolicyLabel.new()
    |> DB.create!()
  end

  # A public project every client may read, its windows checking permissions, and a locked label it
  # does not hold yet.
  defp verdict_rows(_context) do
    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      entries: %{},
      permission_checking?: true,
      windows: %{
        @project_window => Stage.normalize(PolicyProject),
        @other_window => Stage.normalize(PolicyModule1),
        @public_project_window =>
          PolicyProject
          |> Query.filter(public: true)
          |> Stage.normalize()
      }
    })

    project =
      %{public: true}
      |> PolicyProject.new()
      |> DB.create!()

    %{locked: verdict_label("locked"), project: project}
  end

  defp verdicts_patch(project, archivable?) do
    %{
      data: %{"$revisions": %{}, "$verdicts": project_verdicts(archivable?)},
      id: project.id,
      op: :patch_entity,
      type: "Hologram.Test.Fixtures.Policy.Module17"
    }
  end
end
