defmodule Hologram.Sync.SessionTest do
  # async: false - each test writes the query cache's persistent term, shared by the whole node,
  # and starts the sync result store, the evaluator registry and the evaluators supervisor under
  # their registered names, which one test on the node can hold at a time.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Query, only: [add_relationship: 3]
  import Hologram.Test.Stubs
  import Mox

  require Hologram.Query

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.PLT
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Oplog
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Mutation.Record
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Realtime.SSE
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Live
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Session
  alias Hologram.Sync.Sessions
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
  alias Hologram.Test.Fixtures.Policy.Module35, as: PolicyGatedParent
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5

  use_module_stub :query_cache
  use_module_stub :sync_page_windows

  setup :set_mox_global

  @bare_label_window "w_bare_label"
  @board_window "w_board"
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
  @other_replica "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"
  @replica_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @types_hash "00112233445566778899aabbccddeeff"

  setup do
    setup_query_cache(QueryCacheStub, false)
    setup_sync_page_windows(SyncPageWindowsStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      entries: %{},
      permission_checking?: true,
      synced_types: [Module2, PolicyModule1, PolicyModule5],
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

    wait_for_process_cleanup(Sessions.registry())
    start_supervised!(Sessions)

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
  # shape hold_windows/1 uses. A returning session's first read is several messages and a query
  # past the continue that starts it, so the allow is not on a knife edge; a first arrival's fill
  # reads in that continue, so the fill lets the session in itself.
  #
  # A test names what a returning client missed as `gap:` and, when its grants moved, `grants_then:`
  # - the effects and grants the session reads through `:read_gap`. They are handed over as a
  # reader answering them, dated by the gap's last effect as the read deciding the client resumes
  # dates it.
  defp start_session!(opts) do
    test_pid = self()

    # A first arrival fills inside its first callback, which can run before the test lets it in -
    # so the fill lets the session in itself, as a gap reader does.
    read_fill = Keyword.get(opts, :read_fill, &read_fill_in_sandbox/4)

    opts =
      opts
      |> resume_opts()
      |> Keyword.put_new(:client, self())
      |> Keyword.put_new(:outbox, raw: true)
      |> Keyword.put_new(:page, @page)
      |> Keyword.put_new(:policy_hash, @policy_hash)
      |> Keyword.put_new(:types_hash, @types_hash)
      |> Keyword.put(:read_fill, fn entity_type, actor_user_id, replica_id, synced_types ->
        allow_into_sandbox(self(), test_pid)

        read_fill.(entity_type, actor_user_id, replica_id, synced_types)
      end)
      |> Keyword.put_new(:read_named, &read_named_in_sandbox/4)
      |> Keyword.put_new(:read_ids, read_ids_in_sandbox())

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

  # The fill and a catch-up's reading again read in a snapshot of their own, which the test's
  # connection cannot open: it is inside the test's transaction, and a savepoint of the session's
  # would share names with the test's own. So the session reads in the test's transaction, which is
  # the one snapshot every read here sees.
  #
  # And it traps exits from here on, so the end of a test stops it between two messages rather than
  # in the middle of a read: a process killed while it reads takes the test's connection down with
  # it, and the next test's with that.
  defp read_fill_in_sandbox(entity_type, actor_user_id, replica_id, synced_types) do
    Process.flag(:trap_exit, true)

    Fill.read_now(entity_type, actor_user_id, replica_id, synced_types)
  end

  defp read_named_in_sandbox(ids_by_type, actor_user_id, replica_id, synced_types) do
    Process.flag(:trap_exit, true)

    Fill.read_named_now(ids_by_type, actor_user_id, replica_id, synced_types)
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

      Catchup.gap(cursor, actor_user_id, @policy_hash, @types_hash)
    end
  end

  # What a returning client is taken to hold, read by a session that lets itself into the sandbox
  # first, since it reads before a test could let it in - and traps exits from here on, as the other
  # readers below have it, so the end of a test stops it between two messages.
  defp read_ids_in_sandbox do
    test_pid = self()

    fn entity_type, actor_user_id ->
      Process.flag(:trap_exit, true)
      allow_into_sandbox(self(), test_pid)

      Fill.read_ids(entity_type, actor_user_id)
    end
  end

  # Every delta the fill sends a first arrival, up to the marker saying it holds everything.
  # Asleep with nothing left to read: a message still queued is one the session has yet to wake for.
  defp asleep?(session) do
    [message_queue_len: queued, current_function: {_module, function, _arity}] =
      Process.info(session, [:message_queue_len, :current_function])

    queued == 0 and function in [:hibernate, :loop_hibernate]
  end

  defp await_fill(acc \\ []) do
    receive do
      {:sync_deltas, _cursor, deltas, _applied_seq} -> await_fill(acc ++ deltas)
      {:sync_synced, :all, _cursor} -> acc
      {:sync_synced, {:types, _types}, _cursor} -> await_fill(acc)
    after
      1_000 -> flunk("the client was never told it holds everything")
    end
  end

  # Runs the stream's pump over what the session sends until the marker saying the client holds
  # everything is written.
  defp pump_until_filled(conn, session, test_pid) do
    {:cont, conn} = SSE.process_message(conn, nil, nil, sync_session: session)

    if conn.resp_body =~ ~s("scope":"all") do
      send(test_pid, :filled)
    else
      pump_until_filled(conn, session, test_pid)
    end
  end

  # The scopes of the completeness markers in the order they arrive, up to the one saying the client
  # holds everything.
  defp synced_scopes(acc \\ []) do
    receive do
      {:sync_synced, :all, _cursor} -> Enum.reverse([:all | acc])
      {:sync_synced, scope, _cursor} -> synced_scopes([scope | acc])
    after
      1_000 -> flunk("the client was never told it holds everything")
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

      start_session!(gap: [])

      assert_receive {:sync_synced, :all, _cursor}
      assert Evaluators.live() == [{@board_window, Stage.normalize(Module2)}]
    end

    test "holds every window its page reaches" do
      windows(%{@page => [@board_window, @other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(gap: [])

      assert_receive {:sync_synced, :all, _cursor}

      live_window_ids =
        Evaluators.live()
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert live_window_ids == [@board_window, @other_window]
    end

    test "holds nothing for a page this build does not have" do
      windows(%{})

      start_session!(gap: [])

      assert_receive {:sync_synced, :all, _cursor}
      assert Evaluators.live() == []
    end

    # The board window stays outstanding until the test fills it, so what the session took up can
    # be seen before it is caught up and leaves its windows.
    test "skips a window nothing downloads rather than refusing to start" do
      windows(%{@page => ["w_unknown", @board_window]})
      hold_silently(@board_window)

      session = start_session!(gap: [])

      assert Map.keys(:sys.get_state(session).window_refs) == [@board_window]

      finish_filling(session, @board_window)

      assert_receive {:sync_synced, :all, _cursor}
      assert Process.alive?(session)
    end

    # Both sessions are kept catching up by a window that never fills: a session that is caught up
    # has left its windows, and the holder alone would keep the evaluator running.
    test "joins the window a session already holds rather than starting a second evaluator" do
      windows(%{@page => [@board_window, @other_window]})
      holder = hold_windows([@board_window])
      hold_silently(@other_window)

      first = start_session!(gap: [])

      other_client = spawn_link(fn -> Process.sleep(:infinity) end)
      second = start_session!(gap: [], client: other_client)

      :sys.get_state(first)
      :sys.get_state(second)

      [{evaluator, _value}] = Registry.lookup(Evaluator.registry(), @board_window)

      subscribers =
        evaluator
        |> :sys.get_state()
        |> Map.fetch!(:subscribers)
        |> Map.keys()

      assert Enum.sort(subscribers) == Enum.sort([holder, first, second])
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

    # The fill sent the row though no window carries it, so no window's round can say what it is
    # now - it is read as it stands, through the read rules.
    test "tells a returning client about a row no window carries as it stands" do
      row =
        %{public: true, priority: 5}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [%{gap_effect(row.id) | type: PolicyModule1}])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: %{priority: 5}, id: id, op: :put_entity}] = deltas
      assert id == row.id
    end

    test "tells a returning client to drop a row no window carries that is gone" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      DB.delete(PolicyModule1, row.id)

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [%{gap_effect(row.id) | type: PolicyModule1}])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{id: row.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # The row read again carries the replica's batches confirmed by the time it was read, which the
    # gap's effects can say nothing of.
    test "names the number read with a row no window carries" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      Connection.transaction(fn ->
        Record.claim!(@replica_id, 5, nil, "h")
        Record.complete!(@replica_id, 5, %{"dropped" => %{}, "status" => "confirmed"})
      end)

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(
        applied_seq: 3,
        gap: [%{gap_effect(row.id) | type: PolicyModule1}],
        replica_id: @replica_id
      )

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :put_entity}], 5}
      assert id == row.id
    end

    test "tells a returning client to drop a row no window carries that it may no longer read" do
      row = DB.create!(PolicyModule1.new())
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [%{gap_effect(row.id) | type: PolicyModule1}])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{id: row.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # The label gained a message through an edge of the message's, and the label's own set of
    # messages is the client's to file - so the label is read with its set, though no window
    # carries either row.
    test "hands over the target of an edge no window carries, with its set" do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: true,
        synced_types: [Module2, Module28, Module29],
        windows: %{@board_window => Stage.normalize(Module2)}
      })

      label =
        %{name: "urgent"}
        |> Module29.new()
        |> DB.create!()

      message =
        %{body: "hi", position: 1}
        |> Module28.new()
        |> DB.create!()

      EntityOperations.add_relationship(Module28, message.id, :labels, label.id)

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

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

      assert [%{data: %{messages: [message_id]}, op: :put_entity}] =
               Enum.filter(deltas, &(&1.id == label.id))

      assert message_id == message.id
      assert [%{op: :put_entity}] = Enum.filter(deltas, &(&1.id == message.id))
    end

    # A child's container files the set, the child no set of its own, so only the container is read.
    test "reads again only the target of an edge that files the edge's set" do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: true,
        synced_types: [Module2, PolicyModule1, PolicyParent],
        windows: %{@board_window => Stage.normalize(Module2)}
      })

      container = DB.create!(PolicyParent.new())
      child = DB.create!(PolicyModule1.new())

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      edge =
        container.id
        |> gap_effect()
        |> Map.merge(%{
          data: %{"relationship" => "children", "target_id" => child.id},
          op: :add_relationship,
          type: PolicyParent
        })

      test_pid = self()

      read_named = fn ids_by_type, actor_user_id, replica_id, synced_types ->
        send(test_pid, {:read_named, ids_by_type})

        read_named_in_sandbox(ids_by_type, actor_user_id, replica_id, synced_types)
      end

      start_session!(gap: [edge], read_named: read_named)

      assert_receive {:read_named, ids_by_type}
      assert ids_by_type == %{PolicyParent => [container.id]}
    end

    test "reads nothing again when every row the gap names is a window's" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      test_pid = self()

      read_named = fn ids_by_type, actor_user_id, replica_id, synced_types ->
        send(test_pid, {:read_named, ids_by_type})

        read_named_in_sandbox(ids_by_type, actor_user_id, replica_id, synced_types)
      end

      start_session!(gap: [gap_effect(moved.id)], read_named: read_named)

      assert_receive {:sync_synced, :all, _cursor}
      refute_received {:read_named, _ids_by_type}
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

    # The write landed after the read that decided the client resumes, and the window's round
    # already holds it - the frame carrying the row says the write is in, or the client would apply
    # it a second time.
    test "raises the watermark for this replica's batch past the read that decided the client resumes" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_silently(@board_window)

      written = %{gap_effect(moved.id, {900, 1}, ref(@replica_id, 4)) | revisions: %{"c" => 5}}

      session =
        start_session!(applied_seq: 3, gap: [written], gap_end: nil, replica_id: @replica_id)

      ResultStore.put(@board_window, 1, [with_revisions(moved, %{c: 5})])
      send(session, {:round, @board_window, 1, [], nil})

      assert_receive {:sync_deltas, _cursor, [%{id: id}], 4}
      assert id == moved.id
    end

    # The first batch names the row for someone else's write, and the row as it stands already holds
    # this replica's write that only the second batch names - the first frame says it is in.
    test "raises the watermark before the first frame for this replica's batch a later frame names" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_silently(@board_window)

      put_app_env(:sync, rows_per_frame: 1)

      gap = [
        %{gap_effect(moved.id, {900, 1}) | revisions: %{"a" => 3}},
        %{gap_effect(moved.id, {900, 2}, ref(@replica_id, 4)) | revisions: %{"c" => 5}}
      ]

      session = start_session!(applied_seq: 3, gap: gap, replica_id: @replica_id)

      ResultStore.put(@board_window, 1, [with_revisions(moved, %{a: 3, c: 5})])
      send(session, {:round, @board_window, 1, [], nil})

      assert_receive {:sync_deltas, first_cursor, [%{id: id}], first_applied_seq}

      assert {Cursor.decode(first_cursor), id, first_applied_seq} ==
               {{:ok, 900, 1, @policy_hash, @types_hash}, moved.id, 4}
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
      assert Cursor.decode(first_cursor) == {:ok, 900, 2, @policy_hash, @types_hash}
      assert length(first_deltas) == 2

      assert_receive {:sync_deltas, second_cursor, second_deltas, _applied_seq}
      assert Cursor.decode(second_cursor) == {:ok, 900, 4, @policy_hash, @types_hash}
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
      assert_receive {:sync_synced, :all, _cursor}
    end

    test "keeps telling a returning client the news once it has been caught up" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [gap_effect(moved.id)])
      assert_receive {:sync_deltas, _cursor, _caught_up, _applied_seq}
      assert_receive {:sync_synced, :all, _cursor}

      DB.update(Module2, moved.id, %{c: "moved again, this time watched"})
      route([live_effect(:patch_entity, Module2, moved.id, %{"c" => "whatever the log said"})])

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
      cursor = Cursor.encode(tx, seq, @policy_hash, @types_hash)

      DB.update(Module2, moved.id, %{c: "moved while away"})

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      {gap_end_tx, gap_end_seq} = gap_end = last_place()

      start_supervised!(
        {Session,
         client: self(),
         gap_end: gap_end,
         outbox: [raw: true],
         page: @page,
         policy_hash: @policy_hash,
         read_gap: read_gap_from(cursor),
         read_ids: read_ids_in_sandbox(),
         read_named: &read_named_in_sandbox/4,
         types_hash: @types_hash}
      )

      assert_receive {:sync_deltas, frame_cursor, deltas, _applied_seq}

      assert Cursor.decode(frame_cursor) ==
               {:ok, gap_end_tx, gap_end_seq, @policy_hash, @types_hash}

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
      cursor = Cursor.encode(tx, seq, @policy_hash, @types_hash)

      DB.update(Module2, moved.id, %{c: "moved while away"})
      DB.update(Module2, moved.id, %{c: "moved again while away"})

      put_app_env(:sync, gap_limit: 1)

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      test_pid = self()
      read_gap = read_gap_from(cursor)
      read_ids = read_ids_in_sandbox()

      {connection, ref} =
        spawn_monitor(fn ->
          Session.start_link(
            client: test_pid,
            outbox: [raw: true],
            page: @page,
            policy_hash: @policy_hash,
            read_gap: read_gap,
            read_ids: read_ids,
            types_hash: @types_hash
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
        {:sync_synced, :all, _cursor} -> acc
      after
        1_000 -> flunk("the client was never told it was caught up")
      end
    end

    defp cursor_now do
      {tx, seq} = last_place()

      Cursor.encode(tx, seq, @policy_hash, @types_hash)
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

    # The change lands just after the gap was read, so the gap doesn't name it. Its batch reaches the
    # session while it is reading the gap, waits behind the catch-up, and is told once the client is
    # caught up - whole, since it is below the edge the catch-up's reads may have seen part of.
    test "tells a batch routed while the client is being caught up once it is" do
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
      route([live_effect(:patch_entity, Module2, renamed.id, %{"c" => "new title"})], {1, 0})
      send(session, :judge)

      # Read in the order they came: a batch before the marker would pass an assert_receive too.
      assert_receive first
      assert_receive second
      assert {:sync_synced, :all, _cursor} = first
      assert {:sync_deltas, _cursor, [%{data: data, id: id, op: :put_entity}], _seq} = second
      assert id == renamed.id
      assert data.c == "new title"
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

    # The child went public between the two reads, so the parent from the earlier window, read
    # while the client couldn't see the child, lists it once the later window shows it.
    test "lists a row a window read later shows in the rows handed over" do
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

      listing_hidden = %{parent | children: [%{child | public: false}]}

      ResultStore.put(@board_window, 1, [listing_hidden], 1)
      ResultStore.put(@other_window, 1, [child], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               Frame.put_entity(listing_hidden, Frame.row_verdicts(nil, listing_hidden)),
               Frame.put_entity(child, Frame.row_verdicts(nil, child))
             ]
    end

    # A grant given while the client was away reveals the parent, whose list holds a child the
    # client may not see.
    test "hands over a row a grant revealed listing only what the client may see" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      child = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyGatedParent.new())
      Auth.grant_role(user, :viewer, parent)

      windows(%{@page => [@board_window]})
      hold_silently(@board_window)

      missing_id = Entity.generate_id()

      session =
        start_session!(actor_user_id: user.id, gap: [gap_effect(missing_id)], grants_then: [])

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}], 1)
      send(session, {:round, @board_window, 1, [], nil})

      listing_nothing = %{parent | children: []}

      assert caught_up_deltas() == [
               %{
                 id: missing_id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               },
               Frame.put_entity(listing_nothing, Frame.row_verdicts(user.id, listing_nothing))
             ]
    end

    # The grant reveals the parent in the earlier window, read while the client couldn't see the
    # child; the window read later shows the child.
    test "hands over a row a grant revealed listing what a window read later shows" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyGatedParent.new())
      Auth.grant_role(user, :viewer, parent)

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session =
        start_session!(
          actor_user_id: user.id,
          gap: [%{gap_effect(child.id) | type: PolicyModule1}],
          grants_then: []
        )

      listing_hidden = %{parent | children: [%{child | public: false}]}

      ResultStore.put(@board_window, 1, [listing_hidden], 1)
      ResultStore.put(@other_window, 1, [child], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert caught_up_deltas() == [
               Frame.put_entity(child, Frame.row_verdicts(user.id, child)),
               Frame.put_entity(listing_hidden, Frame.row_verdicts(user.id, listing_hidden))
             ]
    end

    # The earlier window carries the parent hidden and listing a child; the window read later shows
    # it without that list. What a hidden copy included is no part of what is handed over.
    test "hands over a row a window read later shows as that window has it" do
      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyGatedParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [%{gap_effect(parent.id) | type: PolicyGatedParent}])

      shown = %{parent | public: true}

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}], 1)
      ResultStore.put(@other_window, 1, [shown], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert caught_up_deltas() == [Frame.put_entity(shown, Frame.row_verdicts(nil, shown))]
    end

    # The catch-up takes the row away, so once it is back in sight the batch that brings it back
    # hands it over whole rather than patching it.
    test "hands a row the catch-up took away over whole once it is back in sight" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [%{gap_effect(row.id) | type: PolicyModule1}])

      ResultStore.put(@board_window, 1, [row], 1)
      ResultStore.put(@other_window, 1, [%{row | public: false}], 2)
      send(session, {:round, @board_window, 1, [], nil})
      send(session, {:round, @other_window, 1, [], nil})

      assert caught_up_deltas() == [
               %{id: row.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]

      route([live_effect(:patch_entity, PolicyModule1, row.id, %{"public" => true})])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [Frame.put_entity(row, Frame.row_verdicts(nil, row))]
    end

    # The grant is taken away while the windows fill, and no round of the window holding the row has
    # told the session yet when the catch-up takes the row away. The grant comes back before one
    # does, so that round has to hand the row over whole.
    test "hands a row a revoked grant took away over whole once the grant is back" do
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
      finish_filling(session, @board_window)

      assert deltas_for(caught_up_deltas(), gated) == [
               %{id: gated.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]

      granted = Oplog.read_type_after(RoleGrant, 0, 0, %{})
      Auth.grant_role(user, :viewer, gated)

      RoleGrant
      |> Oplog.read_type_after(0, 0, %{})
      |> Enum.drop(length(granted))
      |> Enum.map(&Map.put(&1, :mutation_ref, nil))
      |> route()

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{id: id, op: :put_entity}] = deltas
      assert id == gated.id
    end

    # The parent turned private while the windows filled, so the window's last round no longer
    # carries the child the client held under it - which its user may still read, so it stays.
    test "keeps a row that left every window while its user may still read it" do
      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), child) == []
    end

    # The child's grant was taken away while the client was gone, so no round lets it see the child,
    # and the parent turned private takes the child out of the window too. The grants it held before
    # it went away let it see the child, so it may still hold it.
    test "takes away a row a revoked grant covered once it left every window" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      child = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session =
        start_session!(
          actor_user_id: user.id,
          gap: [gap_effect(Entity.generate_id())],
          grants_then: [viewer_grant(user.id, child)]
        )

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), child) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # Kept whole until the catch-up judges it, but a row the client may not read stays out of what
    # the process reports of itself, crash reports included.
    test "reports a row that left a window hidden from the client by its type alone" do
      hidden = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [%{parent | children: [hidden]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [])
      send(session, {:round, @board_window, 2, [], nil})

      {:status, ^session, _module, [_pdict, _sys_state, _parent, _debug, status]} =
        :sys.get_status(session)

      [state] = for {:data, [{~c"State", state}]} <- status, do: state

      assert state.departed[hidden.id] == {:hidden, PolicyModule1}
    end

    # A round carries the values every client's writes set, so the report of a session that stopped
    # while reading one names the round without them.
    test "reports the round it stopped on without the values it carried" do
      transactions = transactions(Entity.generate_id(), ["c"])

      status = %{
        message: {:round, @board_window, 2, transactions, {300, 0}},
        state: %{departed: %{}, queued_parts: []}
      }

      assert Session.format_status(status).message ==
               {:round, @board_window, 2, :redacted, {300, 0}}
    end

    # A row the client could never see says nothing to it when it leaves - windows are shared, and
    # carry rows of every user.
    test "says nothing of a row the client could never see leaving every window" do
      hidden = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [%{parent | children: [hidden]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), hidden) == []
    end

    # The window's previous round left the ring before the next one could be compared with it, so
    # what left the window between them can't be known.
    test "cuts the client off when a window's previous round left the ring before its next one" do
      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [])
      send(session, {:round, @board_window, 1, [], nil})
      settle([], session)

      # Round 4 landing drops round 1 from the ring, while round 2 is still there to be read.
      Enum.each(2..4, &ResultStore.put(@board_window, &1, []))

      ref = Process.monitor(session)
      send(session, {:round, @board_window, 2, [], nil})

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
    end

    # The child leaves the board window, but the other window's last round still lets the client see
    # it, so it hasn't left every window.
    test "keeps a row that left one window while another window's last round shows it" do
      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [])
      send(session, {:round, @board_window, 2, [], nil})

      ResultStore.put(@other_window, 1, [child])
      send(session, {:round, @other_window, 1, [], nil})

      assert deltas_for(caught_up_deltas(), child) == []
    end

    test "keeps a row that left a window and came back to it" do
      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [parent])
      send(session, {:round, @board_window, 2, [], nil})
      ResultStore.put(@board_window, 3, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 3, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), child) == []
    end

    defp start_with_departed_label!(label) do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: true,
        synced_types: [Module2, Module28, Module29, PolicyModule1],
        windows: %{
          @board_window => Stage.normalize(Module2),
          @other_window => other_window_term()
        }
      })

      message =
        %{body: "hi", position: 1}
        |> Module28.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      edge =
        message.id
        |> gap_effect()
        |> Map.merge(%{
          data: %{"relationship" => "labels", "target_id" => label.id},
          op: :add_relationship,
          type: Module28
        })

      session = start_session!(gap: [edge])

      ResultStore.put(@board_window, 1, [%{message | labels: [label]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [message])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)
    end

    # The label left every window and is named only as the target of an edge whose set it files.
    # It is read again and found, so it is handed over - not taken away first and handed back.
    test "hands over once a departed target of a named edge the client may read" do
      label =
        %{name: "urgent"}
        |> Module29.new()
        |> DB.create!()

      start_with_departed_label!(label)

      assert [%{op: :put_entity}] = deltas_for(caught_up_deltas(), label)
    end

    test "takes away a departed target of a named edge that is gone" do
      label =
        %{name: "urgent"}
        |> Module29.new()
        |> DB.create!()

      # Gone before the catch-up reads it, though the windows' rounds still carried it.
      DB.delete(Module29, label.id)
      start_with_departed_label!(label)

      assert deltas_for(caught_up_deltas(), label) == [
               %{id: label.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Entity.Module29"}
             ]
    end

    # The row left every window, but the client may still read it, and since the fill it holds
    # every row it may read - so it is handed over as it stands, once, rather than taken away.
    test "hands over once a row that left every window, that the gap names and the client may read" do
      child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [%{gap_effect(child.id) | type: PolicyModule1}])

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [parent])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert [%{op: :put_entity}] = deltas_for(caught_up_deltas(), child)
    end

    test "takes away once a row that left every window, that the gap names and the client may not read" do
      child = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [%{gap_effect(child.id) | type: PolicyModule1}])

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [parent])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), child) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # The child reads through its parent, which went private while the client was gone, so no round
    # lets the client see the child - but it could before the parent moved, so it may hold it.
    test "takes away a row a moved related row hid once it left every window" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      parent = DB.create!(PolicyModule1.new())

      child =
        %{parent_id: parent.id}
        |> PolicyModule5.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session =
        start_session!(
          actor_user_id: user.id,
          edges: Edges.derive([PolicyModule5]),
          gap: [related_effect(parent.id, PolicyModule1, %{"public" => 1})]
        )

      ResultStore.put(@board_window, 1, [child])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), child) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module5"}
             ]
    end

    # The row left the board window, and the other window's last round carries it hidden since a
    # grant was taken away - the shift takes it away, and nothing takes it away again.
    test "takes away once a row that left every window and that a revoked grant hid" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      child = DB.create!(PolicyModule1.new())
      parent = DB.create!(PolicyParent.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session =
        start_session!(
          actor_user_id: user.id,
          gap: [gap_effect(Entity.generate_id())],
          grants_then: [viewer_grant(user.id, child)]
        )

      ResultStore.put(@board_window, 1, [%{parent | children: [child]}])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [parent])
      send(session, {:round, @board_window, 2, [], nil})

      ResultStore.put(@other_window, 1, [child])
      send(session, {:round, @other_window, 1, [], nil})

      assert deltas_for(caught_up_deltas(), child) == [
               %{id: child.id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Policy.Module1"}
             ]
    end

    # A related row moving into the window's filter brings a row that never changed itself, so the
    # gap doesn't name it - and the window lists it as held already.
    test "hands over a row that entered a window while the client was being caught up" do
      arriving =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [arriving])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), arriving) == [
               Frame.put_entity(arriving, Frame.row_verdicts(nil, arriving))
             ]
    end

    test "hands over nothing of a row that entered a window and left it again" do
      passing =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [passing])
      send(session, {:round, @board_window, 2, [], nil})
      ResultStore.put(@board_window, 3, [])
      send(session, {:round, @board_window, 3, [], nil})

      finish_filling(session, @other_window)

      # Its user may read it, so it is held from before the gap and neither handed over nor taken
      # away.
      assert deltas_for(caught_up_deltas(), passing) == []
    end

    # The row entered two windows and left one of them again - the other window still holds it.
    test "hands over a row that entered two windows and left one of them" do
      arriving =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window, @reach_window]})
      Enum.each([@board_window, @other_window, @reach_window], &hold_silently/1)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      Enum.each([{1, []}, {2, [arriving]}, {3, []}], fn {version, rows} ->
        ResultStore.put(@board_window, version, rows)
        send(session, {:round, @board_window, version, [], nil})
      end)

      Enum.each([{1, []}, {2, [arriving]}], fn {version, rows} ->
        ResultStore.put(@other_window, version, rows)
        send(session, {:round, @other_window, version, [], nil})
      end)

      finish_filling(session, @reach_window)

      assert deltas_for(caught_up_deltas(), arriving) == [
               Frame.put_entity(arriving, Frame.row_verdicts(nil, arriving))
             ]
    end

    # The related row flapped: the row entered, left and entered the window again.
    test "hands over a row that entered a window, left it and entered it again" do
      arriving =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      Enum.each([{1, []}, {2, [arriving]}, {3, []}, {4, [arriving]}], fn {version, rows} ->
        ResultStore.put(@board_window, version, rows)
        send(session, {:round, @board_window, version, [], nil})
        settle([], session)
      end)

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), arriving) == [
               Frame.put_entity(arriving, Frame.row_verdicts(nil, arriving))
             ]
    end

    # A row that entered a window and that a grant given while away reveals is handed over by the
    # shift, and only once.
    test "hands over once a row that entered a window and that a grant revealed" do
      user =
        %{email: "catching-up@example.com"}
        |> Module14.new()
        |> DB.create!()

      arriving = DB.create!(PolicyModule1.new())
      Auth.grant_role(user, :viewer, arriving)

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session =
        start_session!(
          actor_user_id: user.id,
          gap: [gap_effect(Entity.generate_id())],
          grants_then: []
        )

      ResultStore.put(@board_window, 1, [])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [arriving])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), arriving) == [
               Frame.put_entity(arriving, Frame.row_verdicts(user.id, arriving))
             ]
    end

    # Handed over before the gap's batches, in a frame claiming no place, for the same reason as the
    # rows that left every window.
    test "hands over a row that entered a window first, in a frame claiming no place" do
      arriving =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      missing_id = Entity.generate_id()

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(missing_id)])

      ResultStore.put(@board_window, 1, [])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [arriving])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert_receive {:sync_deltas, first_cursor, first_deltas, _applied_seq}
      assert first_cursor == nil
      assert first_deltas == [Frame.put_entity(arriving, Frame.row_verdicts(nil, arriving))]

      assert_receive {:sync_deltas, batch_cursor, [%{id: ^missing_id}], _applied_seq}
      assert batch_cursor != nil
    end

    test "hands over nothing of a row that entered a window hidden from the client" do
      hidden = DB.create!(PolicyModule1.new())

      windows(%{@page => [@board_window, @other_window]})
      hold_silently(@board_window)
      hold_silently(@other_window)

      session = start_session!(gap: [gap_effect(Entity.generate_id())])

      ResultStore.put(@board_window, 1, [])
      send(session, {:round, @board_window, 1, [], nil})
      ResultStore.put(@board_window, 2, [hidden])
      send(session, {:round, @board_window, 2, [], nil})

      finish_filling(session, @other_window)

      assert deltas_for(caught_up_deltas(), hidden) == []
    end

    # The row went public between the two reads, so the window read later outdates the hidden copy.
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
        permission_checking?: true,
        synced_types: [Module2, PolicyModule5],
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
      assert_receive {:sync_synced, :all, _cursor}
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
      assert Cursor.decode(shift_cursor) == {:ok, 900, 7, @policy_hash, @types_hash}
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
    # The fill hands over every row of a type the client may see, so one frame per type is a frame
    # as big as the type's data. Splitting it bounds what a frame costs by the batch rather than by
    # how much the app stores.
    test "splits a type's rows across frames" do
      Enum.each(1..3, &create("row #{&1}"))
      windows(%{@page => [@board_window]})

      put_app_env(:sync, rows_per_frame: 2)

      start_session!([])

      assert_receive {:sync_deltas, nil, first, _applied_seq}
      assert length(first) == 2

      assert_receive {:sync_deltas, nil, second, _applied_seq}
      assert length(second) == 1

      assert_receive {:sync_synced, :all, _cursor}
    end
  end

  describe "start_link/1 - a stream under the heap cap" do
    # The stream's process runs under a heap cap meant for broadcasts piling up behind a slow
    # consumer, and a frame takes many times its own size on the heap while it is encoded. One
    # frame of rows carrying big sets passes the cap on its own if the stream encodes it, so it
    # reaches the stream encoded.
    test "fills a stream running under the heap cap" do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: true,
        synced_types: [Module3],
        windows: %{}
      })

      windows(%{})

      targets = Enum.map(1..100, fn _index -> Module2.new() end)

      rows =
        Enum.map(1..500, fn _index -> %{Module3.new(c_id: Entity.generate_id()) | a: targets} end)

      test_pid = self()

      {stream, ref} =
        spawn_monitor(fn ->
          :ok = SSE.configure_backpressure_safety_net()

          conn =
            :get
            |> Plug.Test.conn("/")
            |> SSE.prepare()

          receive do
            {:session, session} -> pump_until_filled(conn, session, test_pid)
          end
        end)

      # Started the way a stream starts it, with an outbox that encodes, and room for one chunk, so
      # every chunk after the first waits for the pump to say it wrote the one before.
      session =
        start_supervised!(
          {Session,
           client: stream,
           outbox: [max_unwritten: 1],
           page: @page,
           policy_hash: @policy_hash,
           read_fill: fn Module3, _actor_user_id, _replica_id, _synced_types -> {rows, nil} end,
           types_hash: @types_hash}
        )

      send(stream, {:session, session})

      receive do
        :filled -> :ok
        {:DOWN, ^ref, :process, ^stream, reason} -> flunk("the stream ended: #{inspect(reason)}")
      after
        5_000 ->
          Process.exit(stream, :kill)
          flunk("the stream was never filled")
      end
    end
  end

  describe "start_link/1 - a client that falls behind" do
    # The fill's chunks go out only once all but a few of those before them are written - here all
    # but none, with every type sending its marker alone. A type is read before its chunks wait.
    defp start_paced_session!(outbox_opts) do
      windows(%{})
      test_pid = self()

      read_fill = fn entity_type, _actor_user_id, _replica_id, _synced_types ->
        send(test_pid, {:read, entity_type})

        # The first read waits for the test's monitor: a session that gives up at once could
        # otherwise be gone before it is watched.
        if entity_type == Module2 do
          receive do
            :release_read -> :ok
          end
        end

        {[], nil}
      end

      session = start_session!(outbox: outbox_opts, read_fill: read_fill)
      ref = Process.monitor(session)
      send(session, :release_read)

      {session, ref}
    end

    test "cuts a client that takes nothing for as long as the session waits" do
      {session, ref} = start_paced_session!(max_unwritten: 1, stall_ms: 0)

      assert_receive {:DOWN, ^ref, :process, ^session, :client_stalled}

      assert_received {:read, Module2}
      assert_received {:read, PolicyModule1}
      refute_received {:read, PolicyModule5}
    end

    test "stops with nothing to report when the stream asks while it waits" do
      {session, ref} = start_paced_session!(max_unwritten: 1, stall_ms: 5_000)

      # The second type's marker is the one waiting for room.
      assert_receive {:read, PolicyModule1}
      send(session, :sync_stop)

      assert_receive {:DOWN, ^ref, :process, ^session, :normal}
      refute_received {:read, PolicyModule5}
    end

    test "stops with nothing to report when the stream asks while it is idle" do
      {session, ref} = start_paced_session!(raw: true)
      assert_receive {:sync_synced, :all, _cursor}

      send(session, :sync_stop)

      assert_receive {:DOWN, ^ref, :process, ^session, :normal}
    end

    # Over HTTP/2 the stream's process ends with a normal exit, which takes nothing linked to it
    # down.
    test "stops with nothing to report when its client goes" do
      windows(%{})
      client = spawn(fn -> receive(do: (:go -> :ok)) end)
      read_fill = fn _entity_type, _actor_user_id, _replica_id, _synced_types -> {[], nil} end

      session = start_session!(client: client, read_fill: read_fill)
      ref = Process.monitor(session)

      send(client, :go)

      assert_receive {:DOWN, ^ref, :process, ^session, :normal}
    end

    test "takes an answer that arrives while it is idle" do
      {session, ref} = start_paced_session!([])

      # A marker for each of the three types, then the one saying the client holds everything: as
      # many chunks as go out unanswered.
      for _chunk <- 1..4, do: assert_receive({:sync_frame, ^session, _chunk_data})

      send(session, :sync_written)

      assert %{outbox: %{unwritten: 3}} = :sys.get_state(session)
      refute_received {:DOWN, ^ref, :process, ^session, _reason}
    end
  end

  describe "start_link/1 - completeness" do
    # A window's first round tells nothing to a client being filled, and the fill reads after every
    # first round, so one window that never reports holds the whole fill back.
    test "says each synced type is complete, the page's types first, then everything" do
      windows(%{@page => [@other_window], @other_page => [@board_window]})

      start_session!([])

      assert synced_scopes() == [
               {:types, [PolicyModule1]},
               {:types, [Module2]},
               {:types, [PolicyModule5]},
               :all
             ]
    end

    test "fills every synced type for a build with no windows" do
      windows(%{})

      start_session!([])

      assert_receive {:sync_synced, {:types, [Module2]}, nil}
      assert_receive {:sync_synced, {:types, [PolicyModule1]}, nil}
      assert_receive {:sync_synced, {:types, [PolicyModule5]}, nil}
      assert_receive {:sync_synced, :all, _cursor}
    end

    # The marker is what a filled client resumes from: a deltas frame carries no place until the
    # pot is whole, and a client that is filled and then left alone receives no further frame at
    # all - so without this it would hold everything it was sent and have nowhere to come back to.
    test "hands over the place the client may come back from" do
      windows(%{@page => [@board_window]})

      start_session!(fill_place: {200, 0})

      assert_receive {:sync_synced, :all, cursor}
      assert cursor == Cursor.encode(200, 0, @policy_hash, @types_hash)
    end

    # The claim a place makes is "everything up to here is applied", which a client holding some
    # types of several cannot honour.
    test "names no place on the types markers of a first arrival" do
      windows(%{@page => [@board_window]})

      start_session!(fill_place: {200, 0})

      assert_receive {:sync_synced, {:types, [Module2]}, cursor}
      assert cursor == nil
    end

    # A client that came back kept what it had and is told only what moved, so nothing is filled
    # and nothing is complete type by type - it is told it holds everything, with a place.
    test "tells a client that came back it holds everything, with a place" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_windows([@board_window, @other_window])

      start_session!(fill_place: {200, 0}, gap: [])

      assert_receive {:sync_synced, :all, cursor}
      assert cursor == Cursor.encode(200, 0, @policy_hash, @types_hash)
      refute_received {:sync_synced, {:types, _types}, _cursor}
    end
  end

  describe "start_link/1 - first rows" do
    test "sends the rows of a synced type" do
      task = create("first")
      windows(%{@page => [@board_window]})

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

    test "sends nothing for a type holding no rows" do
      windows(%{@page => [@board_window]})

      start_session!([])

      assert_receive {:sync_synced, :all, _cursor}
      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end

    test "fills a synced type no window reads" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window]})

      start_session!([])

      assert Enum.any?(await_fill(), &(&1.id == row.id))
    end

    # The number is what lands the client's pending batches on these rows, so it is the one read
    # with them - a batch confirmed since the session began is in them.
    test "carries the number read with the rows" do
      create("first")

      Connection.transaction(fn ->
        Record.claim!(@replica_id, 5, nil, "h")
        Record.complete!(@replica_id, 5, %{"dropped" => %{}, "status" => "confirmed"})
      end)

      windows(%{@page => [@board_window]})

      start_session!(applied_seq: 3, replica_id: @replica_id)

      assert_receive {:sync_deltas, nil, _deltas, 5}
    end

    # Every batch the session's own number counts committed before the read, so its writes are in
    # the rows too.
    test "never names a number below the one the session was given" do
      create("first")

      Connection.transaction(fn ->
        Record.claim!(@replica_id, 5, nil, "h")
        Record.complete!(@replica_id, 5, %{"dropped" => %{}, "status" => "confirmed"})
      end)

      windows(%{@page => [@board_window]})

      start_session!(applied_seq: 7, replica_id: @replica_id)

      assert_receive {:sync_deltas, nil, _deltas, 7}
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

      start_session!([])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = deltas
      assert data.id == readable.id
    end

    test "says it is done once every synced type has been sent" do
      task = create("first")

      readable =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window, @other_window]})

      start_session!([])

      # What came before the marker, so a type sent after it is missing here.
      put_ids =
        await_fill()
        |> Enum.filter(&(&1.op == :put_entity))
        |> Enum.map(& &1.id)

      assert Enum.sort(put_ids) == Enum.sort([task.id, readable.id])
    end

    test "fills a client on a page reaching no window" do
      task = create("first")
      windows(%{@page => []})

      start_session!([])

      assert [%{id: id, op: :put_entity}] = await_fill()
      assert id == task.id
    end
  end

  describe "handle :live" do
    # A batch as the dispatcher reads it, routed to every session on the node the way the
    # dispatcher routes it: through the live router, which reads what the batch means for each.
    # Read, unless a test says otherwise, from past every transaction that has finished - past the
    # fill's edge, so what the session holds is trusted.
    defp route(effects, place \\ nil) do
      {tx, _seq} = place = place || {Oplog.current_xmax() + 1, 0}

      Live.route([{tx, Enum.map(effects, &Map.put_new(&1, :tx, tx))}], place)
    end

    defp live_effect(op, type, entity_id, data, mutation_ref \\ nil) do
      %{
        data: data,
        entity_id: entity_id,
        mutation_ref: mutation_ref,
        old: nil,
        op: op,
        type: type
      }
    end

    # Waits, inside the session, until the test has routed the batch it is about to send.
    defp assert_receive_from_test do
      receive do
        :routed -> :ok
      after
        1_000 -> raise "the test never routed the batch"
      end
    end

    # The session reads the part only once it has handled what it was sent before it.
    defp await_live(session) do
      :sys.get_state(session)

      :ok
    end

    test "joins the node's sessions and takes up no window" do
      windows(%{@page => [@board_window]})

      session = start_session!([])
      await_fill()

      assert Sessions.list() == [{session, nil}]
      assert Evaluators.live() == []
    end

    test "hands over a row created while the client watches, whole" do
      windows(%{})

      start_session!([])
      await_fill()

      task = create("created")
      route([live_effect(:put_entity, Module2, task.id, %{"a" => true, "c" => "created"})])

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :put_entity}], nil}
      assert id == task.id
      assert data.c == "created"
    end

    # No window reads the type, which is what a type only an action reads looks like.
    test "patches a row the fill sent with what the batch wrote, as it stands" do
      task = create("before")
      windows(%{})

      start_session!([])
      await_fill()

      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "whatever the log said"})])

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :patch_entity}], nil}
      assert id == task.id
      assert data.c == "after"
    end

    test "tells the client to drop a row its user may no longer read" do
      gated =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{})

      start_session!([])
      await_fill()

      DB.update!(PolicyModule1, gated.id, public: false)
      route([live_effect(:patch_entity, PolicyModule1, gated.id, %{"public" => false})])

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :unsync_entity}], nil}
      assert id == gated.id
    end

    test "tells nothing of a row its user may not read" do
      windows(%{})

      start_session!([])
      await_fill()

      hidden =
        %{public: false}
        |> PolicyModule1.new()
        |> DB.create!()

      route([live_effect(:put_entity, PolicyModule1, hidden.id, %{"public" => false})])

      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end

    test "passes over a batch the fill already holds" do
      task = create("before")
      windows(%{})

      session = start_session!(fill_place: {200, 0})
      await_fill()

      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {150, 0})
      await_live(session)

      refute_received {:sync_deltas, _cursor, _deltas, _applied_seq}
    end

    test "names the number of this replica's batches the batch holds" do
      task = create("before")
      windows(%{})

      start_session!(replica_id: @replica_id)
      await_fill()

      DB.update!(Module2, task.id, c: "after")

      effect =
        live_effect(:patch_entity, Module2, task.id, %{"c" => "after"}, ref(@replica_id, 7))

      route([effect])

      assert_receive {:sync_deltas, _cursor, _deltas, 7}
    end

    test "claims the place the batch was read from, under the session's rules and types" do
      task = create("before")
      windows(%{})

      start_session!(fill_place: {200, 0})
      assert_receive {:sync_synced, :all, fill_cursor}
      assert fill_cursor == Cursor.encode(200, 0, @policy_hash, @types_hash)
      flush_messages()

      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {300, 0})

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert cursor == Cursor.encode(300, 0, @policy_hash, @types_hash)
    end

    test "hands over every row of a type a grant given to its user opens up, and drops them when it is taken" do
      user =
        %{email: "viewer@example.com"}
        |> Module14.new()
        |> DB.create!()

      private =
        %{public: false}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{})

      start_session!(actor_user_id: user.id)
      await_fill()

      before = Oplog.read_type_after(RoleGrant, 0, 0, %{})
      Auth.grant_role(user, :viewer, PolicyModule1)

      RoleGrant
      |> Oplog.read_type_after(0, 0, %{})
      |> Enum.drop(length(before))
      |> Enum.map(&Map.put(&1, :mutation_ref, nil))
      |> route()

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :put_entity}], _applied_seq}
      assert id == private.id

      granted = Oplog.read_type_after(RoleGrant, 0, 0, %{})
      Auth.revoke_role(user, :viewer, PolicyModule1)

      RoleGrant
      |> Oplog.read_type_after(0, 0, %{})
      |> Enum.drop(length(granted))
      |> Enum.map(&Map.put(&1, :mutation_ref, nil))
      |> route({400, 0})

      assert_receive {:sync_deltas, _cursor, [%{id: ^id, op: :unsync_entity}], _applied_seq}
    end

    # The client's batch 8 commits after the batch holding its batch 7 was read, and before the
    # rows were, so the frame claims 8 - and hands the row over whole, since a patch of what batch 7
    # wrote would leave the client showing nothing of batch 8's other writes to it. The session
    # keeps 7, what it was told.
    test "hands a row over whole under a later batch of this replica's the rows hold" do
      task = create("before")
      windows(%{})

      session = start_session!(replica_id: @replica_id)
      await_fill()

      DB.update!(Module2, task.id, c: "overtaken")
      batch_tx = Oplog.current_xmax() + 1
      overtake(task, batch_tx + 1, 8)

      effect =
        live_effect(:patch_entity, Module2, task.id, %{"c" => "after"}, ref(@replica_id, 7))

      route([effect], {batch_tx, 0})

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :put_entity}], 8}
      assert id == task.id
      assert data.c == "overtaken"
      assert :sys.get_state(session).applied_seq == 7

      # Batch 8 overtakes the next batch too, and the session still holds 7, so it goes out whole.
      overtake(task, batch_tx + 2, 8)
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {batch_tx + 1, 0})

      assert_receive {:sync_deltas, _cursor, [%{id: ^id, op: :put_entity}], 8}
    end

    test "hands a row over whole under a later batch of this replica's a batch of others' meets" do
      task = create("before")
      windows(%{})

      start_session!(replica_id: @replica_id)
      await_fill()

      DB.update!(Module2, task.id, c: "overtaken")
      batch_tx = Oplog.current_xmax() + 1
      overtake(task, batch_tx + 1, 8)

      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {batch_tx, 0})

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :put_entity}], 8}
      assert id == task.id
    end

    # The later batch is one the session already told, so the rows hold nothing it hasn't.
    test "patches under its own number a batch that only an already told batch overtook" do
      task = create("before")
      windows(%{})

      start_session!(applied_seq: 9, replica_id: @replica_id)
      await_fill()

      DB.update!(Module2, task.id, c: "after")
      batch_tx = Oplog.current_xmax() + 1
      overtake(task, batch_tx + 1, 8)

      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {batch_tx, 0})

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :patch_entity}], 9}
      assert id == task.id
    end

    test "passes over another replica's batches, and never lowers the number" do
      task = create("before")
      windows(%{})

      start_session!(applied_seq: 5, replica_id: @replica_id)
      await_fill()

      DB.update!(Module2, task.id, c: "after")

      route([
        live_effect(:patch_entity, Module2, task.id, %{"c" => "after"}, ref(@other_replica, 9))
      ])

      assert_receive {:sync_deltas, _cursor, _deltas, 5}

      DB.update!(Module2, task.id, c: "again")

      route([
        live_effect(:patch_entity, Module2, task.id, %{"c" => "again"}, ref(@replica_id, 2))
      ])

      assert_receive {:sync_deltas, _cursor, _deltas, 5}
    end

    test "tells a batch with a transaction at the fill's place" do
      task = create("before")
      windows(%{})

      start_session!(fill_place: {200, 0})
      await_fill()

      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {200, 0})

      assert_receive {:sync_deltas, _cursor, [%{id: id}], _applied_seq}
      assert id == task.id
    end

    test "splits the rows a batch hands over across frames, everything else with the first" do
      gated =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{})
      put_app_env(:sync, rows_per_frame: 2)

      start_session!([])
      await_fill()

      created = Enum.map(1..3, &create("row #{&1}"))
      DB.update!(PolicyModule1, gated.id, public: false)

      created
      |> Enum.map(&live_effect(:put_entity, Module2, &1.id, %{"a" => true, "c" => &1.c}))
      |> Enum.concat([live_effect(:patch_entity, PolicyModule1, gated.id, %{"public" => false})])
      |> route()

      assert_receive {:sync_deltas, _cursor, first, _applied_seq}
      assert_receive {:sync_deltas, _cursor, second, _applied_seq}

      assert Enum.count(first, &(&1.op == :put_entity)) == 2
      assert Enum.any?(first, &(&1.op == :unsync_entity))
      assert Enum.map(second, & &1.op) == [:put_entity]
    end

    # A client keeps each frame's cursor as it lands, so one cut off after the first frame would
    # come back past the second if the first claimed the batch's place.
    test "dates only the last frame of a batch split across frames" do
      windows(%{})
      put_app_env(:sync, rows_per_frame: 2)

      start_session!([])
      await_fill()

      1..3
      |> Enum.map(&create("row #{&1}"))
      |> Enum.map(&live_effect(:put_entity, Module2, &1.id, %{"a" => true, "c" => &1.c}))
      |> route()

      assert_receive {:sync_deltas, first_cursor, _first, _applied_seq}
      assert_receive {:sync_deltas, last_cursor, _last, _applied_seq}

      assert first_cursor == nil
      assert last_cursor != nil
    end

    test "tells a batch queued during the fill once the fill is over, dated" do
      task = create("before")
      windows(%{})
      test_pid = self()

      # The batch reaches the session while it reads its first type, as one routed then would.
      read_fill = fn entity_type, actor_user_id, replica_id, synced_types ->
        if entity_type == Module2 do
          send(test_pid, :routing)
          assert_receive_from_test()
        end

        read_fill_in_sandbox(entity_type, actor_user_id, replica_id, synced_types)
      end

      session = start_session!(read_fill: read_fill)

      assert_receive :routing, 1_000
      DB.update!(Module2, task.id, c: "during")

      # A batch queued during the fill holds transactions that finished before its edge, so it is
      # told without trusting what the session holds.
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "during"})], {1, 0})
      send(session, :routed)

      await_fill()

      assert_receive {:sync_deltas, cursor, [%{data: data, id: id, op: :put_entity}],
                      _applied_seq}

      assert id == task.id
      assert data.c == "during"
      assert cursor != nil
    end

    test "hands over whole every row a type read again names, for a batch below the fill's edge" do
      user =
        %{email: "viewer@example.com"}
        |> Module14.new()
        |> DB.create!()

      public =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{})

      start_session!(actor_user_id: user.id)
      await_fill()

      before = Oplog.read_type_after(RoleGrant, 0, 0, %{})
      Auth.grant_role(user, :viewer, PolicyModule1)

      # Dated below the fill's edge, as a batch the fill may have seen part of is.
      RoleGrant
      |> Oplog.read_type_after(0, 0, %{})
      |> Enum.drop(length(before))
      |> Enum.map(&Map.merge(&1, %{mutation_ref: nil, tx: 1}))
      |> route({1, 0})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert Enum.any?(deltas, &(&1.op == :put_entity and &1.id == public.id))
    end

    test "stops when a part arrives under a data model on hold" do
      windows(%{})

      read_fill = fn entity_type, actor_user_id, replica_id, synced_types ->
        if Process.get(:filled) do
          raise Hologram.StaleModelError
        end

        read_fill_in_sandbox(entity_type, actor_user_id, replica_id, synced_types)
      end

      session = start_session!(read_fill: read_fill)
      await_fill()

      # From here on the session's reads find the model on hold.
      :sys.replace_state(session, fn state ->
        Process.put(:filled, true)

        state
      end)

      ref = Process.monitor(session)

      part = %{
        checked: %{},
        overtaking_seqs: %{},
        own_seqs: %{},
        pair_effects: %{},
        pairs: %{},
        place: {Oplog.current_xmax() + 1, 0},
        readable: %{},
        synced_types: [PolicyModule1],
        tx_range: {Oplog.current_xmax() + 1, Oplog.current_xmax() + 1},
        verdicts: %{},
        whole_types: [PolicyModule1],
        written: %{}
      }

      send(session, {:live, part})

      assert_receive {:DOWN, ^ref, :process, ^session, {:shutdown, :model_held}}
    end

    test "stops when its client ends" do
      windows(%{})

      client =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      session = start_session!(client: client)
      ref = Process.monitor(session)
      wait_until(fn -> Sessions.list() == [{session, nil}] end)

      send(client, :stop)

      assert_receive {:DOWN, ^ref, :process, ^session, :normal}, 1_000

      # The registry clears a dead session's entry on its own time.
      wait_until(fn -> Sessions.list() == [] end)
    end

    test "stops when the node's session list is replaced" do
      windows(%{})

      session = start_session!([])
      await_fill()
      ref = Process.monitor(session)

      stop_supervised!(Sessions.registry())

      assert_receive {:DOWN, ^ref, :process, ^session, :shutdown}
    end

    test "reports a part it is reading without what the part holds" do
      status =
        Session.format_status(%{
          message: {:live, %{readable: %{}}},
          state: %{departed: %{}, queued_parts: []}
        })

      assert status.message == {:live, :redacted}
    end

    test "reports the parts it keeps while its client is caught up by their count alone" do
      renamed = create("kept title")
      windows(%{@page => [@board_window, @other_window]})
      prefill([@board_window])
      hold_silently(@other_window)

      session = start_session!(gap: [])
      :sys.get_state(session)

      route([live_effect(:patch_entity, Module2, renamed.id, %{"c" => "kept title"})])

      {:status, ^session, _module, [_pdict, _sys_state, _parent, _debug, status]} =
        :sys.get_status(session)

      [state] = for {:data, [{~c"State", state}]} <- status, do: state

      assert state.queued_parts == 1
    end
  end

  describe "handle :live - coming back" do
    test "tells a client caught up about a change to a row no window carries" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [])
      assert_receive {:sync_synced, :all, _cursor}

      DB.update!(PolicyModule1, row.id, priority: 5)
      route([live_effect(:patch_entity, PolicyModule1, row.id, %{"priority" => 5})])

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :patch_entity}], _seq}
      assert id == row.id
      assert data.priority == 5
    end

    test "joins the node's sessions before its windows fill" do
      windows(%{@page => [@board_window]})
      hold_silently(@board_window)

      session = start_session!(gap: [])
      :sys.get_state(session)

      assert Sessions.list() == [{session, nil}]
    end

    test "leaves its windows once caught up" do
      windows(%{@page => [@board_window]})
      holder = hold_windows([@board_window])

      session = start_session!(gap: [])
      assert_receive {:sync_synced, :all, _cursor}

      [{evaluator, _value}] = Registry.lookup(Evaluator.registry(), @board_window)
      :sys.get_state(session)

      assert Map.keys(:sys.get_state(evaluator).subscribers) == [holder]
    end

    # Both batches reach the session while it waits for its last window, so it keeps them and
    # tells them, in the order they came, once the client is caught up.
    test "tells the batches routed while it waits for a window once the client is caught up" do
      renamed = create("old title")
      windows(%{@page => [@board_window, @other_window]})
      prefill([@board_window])
      hold_silently(@other_window)

      session = start_session!(gap: [])
      :sys.get_state(session)

      DB.update(Module2, renamed.id, %{c: "new title"})
      route([live_effect(:patch_entity, Module2, renamed.id, %{"c" => "new title"})], {1, 0})
      DB.update(Module2, renamed.id, %{c: "newer title"})
      route([live_effect(:patch_entity, Module2, renamed.id, %{"c" => "newer title"})], {2, 0})

      :sys.get_state(session)
      refute_received {:sync_deltas, _cursor, _deltas, _seq}

      finish_filling(session, @other_window)

      assert_receive {:sync_synced, :all, _cursor}
      assert_receive {:sync_deltas, _cursor, [%{data: first, id: id, op: :put_entity}], _seq}
      assert_receive {:sync_deltas, _cursor, [%{data: second, op: :put_entity}], _seq}
      assert id == renamed.id
      assert {first.c, second.c} == {"new title", "newer title"}
    end

    # The row's user loses it after the gap was read, so the gap doesn't name it - and the batch,
    # finding the row held, takes it away.
    test "takes away a row its user lost while the client was being caught up" do
      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      windows(%{@page => [@board_window]})
      prefill([@board_window])

      test_pid = self()
      read_from_cursor = read_gap_from(cursor_now())

      read_gap = fn ->
        gap = read_from_cursor.()
        send(test_pid, {:gap_read, self()})

        receive do
          :judge -> gap
        end
      end

      session = start_session!(gap_end: nil, read_gap: read_gap)
      assert_receive {:gap_read, ^session}

      DB.update!(PolicyModule1, row.id, public: false)
      route([live_effect(:patch_entity, PolicyModule1, row.id, %{"public" => false})], {1, 0})
      send(session, :judge)

      # Read in the order they came: a batch before the marker would pass an assert_receive too.
      assert_receive first
      assert_receive second
      assert {:sync_synced, :all, _cursor} = first
      assert {:sync_deltas, _cursor, [%{id: id, op: :unsync_entity}], _seq} = second
      assert id == row.id
    end

    # The row is created after the session read what its user may read and before the gap, so the
    # catch-up hands it over - and the session has to take it as held for the batch that hides it
    # to take it away.
    test "takes a row the catch-up handed over as one the client holds" do
      create("so the log has a place to come back from")
      windows(%{@page => [@board_window]})
      prefill([@board_window])

      test_pid = self()
      read_from_cursor = read_gap_from(cursor_now())

      # Holds the session between reading what its user may read and reading the gap.
      read_gap = fn ->
        send(test_pid, {:ids_read, self()})

        receive do
          :read_gap -> read_from_cursor.()
        end
      end

      session = start_session!(gap_end: nil, read_gap: read_gap)
      assert_receive {:ids_read, ^session}

      row =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      send(session, :read_gap)

      assert [%{id: id, op: :put_entity}] = caught_up_deltas()
      assert id == row.id

      DB.update!(PolicyModule1, row.id, public: false)
      route([live_effect(:patch_entity, PolicyModule1, row.id, %{"public" => false})])

      assert_receive {:sync_deltas, _cursor, [%{id: ^id, op: :unsync_entity}], _seq}
    end

    test "tells the kept batches after the marker" do
      renamed = create("old title")
      windows(%{@page => [@board_window, @other_window]})
      prefill([@board_window])
      hold_silently(@other_window)

      session = start_session!(gap: [])
      :sys.get_state(session)

      DB.update(Module2, renamed.id, %{c: "new title"})
      route([live_effect(:patch_entity, Module2, renamed.id, %{"c" => "new title"})], {1, 0})
      :sys.get_state(session)

      finish_filling(session, @other_window)

      # Read in the order they came: a marker after the batch would pass an assert_receive too.
      assert_receive first
      assert_receive second
      assert {:sync_synced, :all, _cursor} = first
      assert {:sync_deltas, _cursor, [%{op: :put_entity}], _seq} = second
    end

    # What the catch-up read and judged is garbage once the client is caught up, and a session can
    # sit idle for as long as its client stays.
    test "sleeps once the client is caught up" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      session = start_session!(gap: [])
      assert_receive {:sync_synced, :all, _cursor}

      wait_until(fn -> asleep?(session) end)
    end

    test "sleeps after a round that reaches it once it has left its windows" do
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      session = start_session!(gap: [])
      assert_receive {:sync_synced, :all, _cursor}
      wait_until(fn -> asleep?(session) end)

      send(session, {:round, @board_window, 2, [], nil})

      wait_until(fn -> asleep?(session) end)
    end

    test "sleeps after a part once nothing else is queued" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      session = start_session!(gap: [])
      assert_receive {:sync_synced, :all, _cursor}
      wait_until(fn -> asleep?(session) end)

      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})])
      assert_receive {:sync_deltas, _cursor, [%{op: :patch_entity}], _seq}

      wait_until(fn -> asleep?(session) end)
    end

    test "hands over whole a row a batch below the catch-up's edge names, held or not" do
      task = create("before")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(gap: [])
      assert_receive {:sync_synced, :all, _cursor}

      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {1, 0})

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :put_entity}], _seq}
      assert id == task.id
      assert data.c == "after"
    end
  end

  describe "handle :live - sets" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: false,
        synced_types: [PolicyLabel, PolicyProject],
        windows: %{}
      })

      project =
        %{public: true}
        |> PolicyProject.new()
        |> DB.create!()

      %{project: project}
    end

    # The label type declares no read rule, so its rows reach no client - which is what a row the
    # project's set names, gone or hidden by the time its own type is read, looks like to the
    # session.
    test "tells the removal of a pair naming a row its set named and the client never got", %{
      project: project
    } do
      windows(%{})
      never_sent_id = Ecto.UUID.generate()

      read_fill = fn entity_type, actor_user_id, replica_id, synced_types ->
        {rows, applied_seq} =
          read_fill_in_sandbox(entity_type, actor_user_id, replica_id, synced_types)

        named = Enum.map(rows, &%{&1 | labels: [%PolicyLabel{id: never_sent_id}]})

        {if(entity_type == PolicyProject, do: named, else: rows), applied_seq}
      end

      start_session!(read_fill: read_fill)
      await_fill()

      data = %{"relationship" => "labels", "target_id" => never_sent_id}
      route([live_effect(:del_relationship, PolicyProject, project.id, data)])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      assert deltas == [
               %{
                 data: %{relationship: "labels", target_id: never_sent_id},
                 id: project.id,
                 op: :del_relationship,
                 type: "Hologram.Test.Fixtures.Policy.Module17"
               }
             ]
    end

    # A batch whose transactions the fill's reads may have seen part of, so a row it made readable
    # can be held while the rows read before it name nothing of it.
    test "hands over whole the rows of a batch below the fill's edge", %{project: project} do
      windows(%{})

      start_session!([])
      await_fill()

      other =
        %{public: true}
        |> PolicyProject.new()
        |> DB.create!()

      DB.update!(PolicyProject, project.id, name: "renamed")

      route(
        [
          live_effect(:put_entity, PolicyProject, other.id, %{"public" => true}),
          live_effect(:patch_entity, PolicyProject, project.id, %{"name" => "renamed"})
        ],
        {1, 0}
      )

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}

      told =
        deltas
        |> Enum.map(&{&1.op, &1.id})
        |> Enum.sort()

      assert told == Enum.sort([{:put_entity, project.id}, {:put_entity, other.id}])
    end
  end

  describe "handle :live - overtaken" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: false,
        synced_types: [Module28, Module29],
        windows: %{}
      })

      :ok
    end

    # The label goes out whole under batch 8's number, while the pair naming it is filed under the
    # message the client already holds, which the frame doesn't restate - so the pair goes in a
    # frame of its own, under the number the session was told.
    test "tells the pairs under a held row apart from the rows it hands over whole" do
      label =
        %{name: "before"}
        |> Module29.new()
        |> DB.create!()

      message =
        %{body: "hi", position: 1}
        |> Module28.new()
        |> DB.create!()

      :ok = EntityOperations.add_relationship(Module28, message.id, :labels, label.id)
      windows(%{})

      start_session!(replica_id: @replica_id)
      await_fill()

      DB.update!(Module29, label.id, name: "overtaken")
      batch_tx = Oplog.current_xmax() + 1
      overtake(label, batch_tx + 1, 8)

      effect =
        live_effect(:patch_entity, Module29, label.id, %{"name" => "after"}, ref(@replica_id, 7))

      route([effect], {batch_tx, 0})

      assert_receive {:sync_deltas, rows_cursor, [%{id: label_id, op: :put_entity}], 8}
      assert label_id == label.id

      assert_receive {:sync_deltas, pairs_cursor, [%{data: data, id: holder_id, op: op}], 7}
      assert {op, holder_id, data.target_id} == {:add_relationship, message.id, label.id}

      # The pairs frame is the batch's last, so it alone claims the batch's place.
      assert rows_cursor == nil
      assert pairs_cursor != nil
    end

    # The type is read again whole after the batch, and the read holds this client's batch 8,
    # which the session never told - so its frames claim 8, the pair under the held message goes
    # apart under the session's 7, and the session keeps 7.
    test "claims a reread's number in its frames without taking it" do
      message =
        %{body: "hi", position: 1}
        |> Module28.new()
        |> DB.create!()

      windows(%{})

      read_fill = fn entity_type, actor_user_id, replica_id, synced_types ->
        {rows, read_seq} =
          read_fill_in_sandbox(entity_type, actor_user_id, replica_id, synced_types)

        {rows, if(Process.get(:reread?), do: 8, else: read_seq)}
      end

      session = start_session!(applied_seq: 7, read_fill: read_fill, replica_id: @replica_id)
      await_fill()

      :sys.replace_state(session, fn state ->
        Process.put(:reread?, true)

        state
      end)

      label =
        %{name: "arrived"}
        |> Module29.new()
        |> DB.create!()

      :ok = EntityOperations.add_relationship(Module28, message.id, :labels, label.id)

      tx = Oplog.current_xmax() + 1

      part = %{
        checked: %{},
        overtaking_seqs: %{},
        own_seqs: %{},
        pair_effects: %{},
        pairs: %{},
        place: {tx, 0},
        readable: %{},
        synced_types: [Module28, Module29],
        tx_range: {tx, tx},
        verdicts: %{},
        whole_types: [Module29],
        written: %{}
      }

      send(session, {:live, part})

      assert_receive {:sync_deltas, _cursor, [%{id: label_id, op: :put_entity}], 8}
      assert label_id == label.id

      assert_receive {:sync_deltas, _cursor, [%{id: holder_id, op: :add_relationship}], 7}
      assert holder_id == message.id
      assert :sys.get_state(session).applied_seq == 7
    end
  end

  describe "handle :live - verdicts" do
    setup :verdict_rows

    # The pair moves no value of the project, but the set its archive rule reads.
    test "sends the verdicts a batch moved on a held row in a patch naming no value", %{
      locked: locked,
      project: project
    } do
      windows(%{})

      start_session!([])
      await_fill()

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)

      data = %{"relationship" => "labels", "target_id" => locked.id}
      route([live_effect(:add_relationship, PolicyProject, project.id, data)])

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, false)]
    end

    test "sends nothing when a batch moves what a held row's verdicts read and not the verdicts",
         %{project: project} do
      loose = verdict_label("loose")
      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, loose.id)
      windows(%{})

      start_session!([])
      await_fill()

      DB.update!(PolicyLabel, loose.id, name: "still loose")
      route([live_effect(:patch_entity, PolicyLabel, loose.id, %{"name" => "still loose"})])

      refute_receive {:sync_deltas, _cursor, _deltas, _applied_seq}, 100
    end

    # The part says the project can't be archived while the database says it can, so what goes out
    # is the part's - read in the batch's recheck - and nothing the session worked out.
    test "sends a held row the verdicts its part carries", %{project: project} do
      windows(%{})

      session = start_session!([])
      await_fill()

      send(session, {:live, verdicts_part(project, project_verdicts(false))})

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert deltas == [verdicts_patch(project, false)]
    end

    test "hands a row over with the verdicts its part carries" do
      windows(%{})

      session = start_session!([])
      await_fill()

      arrived =
        %{public: true}
        |> PolicyProject.new()
        |> DB.create!()

      send(session, {:live, verdicts_part(arrived, project_verdicts(false))})

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :put_entity}], _seq}
      assert id == arrived.id
      assert data[:"$verdicts"] == project_verdicts(false)
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
    # While the client is being caught up: once it is, the session has left its windows.
    test "cuts the client off when an evaluator it reads stops" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_silently(@board_window)
      hold_windows([@other_window])

      session = start_session!(gap: [])

      [{evaluator, _value}] = Registry.lookup(Evaluator.registry(), @other_window)

      # Killed between rounds, not in the middle of the one the session asked for, which would take
      # the test's connection down with it.
      :sys.get_state(session)
      :sys.get_state(evaluator)

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

    # An evaluator stopping after the session was cut is not why the session ends. The board window
    # never fills, so the session is still being caught up and reads the other window's rounds.
    test "ends a session already cut for the reason it was cut" do
      windows(%{@page => [@board_window], @other_page => [@other_window]})
      hold_silently(@board_window)
      hold_windows([@other_window])

      session = start_session!(gap: [])
      ref = Process.monitor(session)
      :sys.suspend(session)

      # A round the ring no longer holds cuts the session, and the evaluator's :DOWN is read before
      # the cut message the round queued.
      send(session, {:round, @other_window, 999, [], nil})
      send(session, {:DOWN, make_ref(), :process, self(), :gone})

      :sys.resume(session)

      assert_receive {:DOWN, ^ref, :process, ^session, :behind_the_ring}
    end
  end

  describe "start_link/1 - coming back, the place a frame claims" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: true,
        synced_types: [Module2],
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
    # A returning client kept what it had, so it can date its store from the first frame - there is
    # no half-filled state for it to misreport. What it is dated BY is the last effect in the batch
    # rather than the fill place, which is what lets a replay be picked up where it stopped.
    test "dates each replayed batch by the last effect in it" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      start_session!(fill_place: {200, 0}, gap: [gap_effect(moved.id, {900, 7})])

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 7, @policy_hash, @types_hash}
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
      assert Cursor.decode(cursor) == {:ok, 900, 7, @policy_hash, @types_hash}
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
      assert Cursor.decode(cursor) == {:ok, 900, 7, other_policy_hash, @types_hash}
    end

    test "dates its places with the types it was started with" do
      moved = create("moved while away")
      windows(%{@page => [@board_window]})
      hold_windows([@board_window])

      other_types_hash = "ffeeddccbbaa99887766554433221100"

      start_session!(
        fill_place: {200, 0},
        gap: [gap_effect(moved.id, {900, 7})],
        types_hash: other_types_hash
      )

      assert_receive {:sync_deltas, cursor, _deltas, _applied_seq}
      assert Cursor.decode(cursor) == {:ok, 900, 7, @policy_hash, other_types_hash}
    end
  end

  describe "start_link/1 - coming back over reach" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: true,
        synced_types: [Module2, Module26, Module28, Module29, Module3],
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

    # The message stays with the client through the message window, so nothing re-puts it - the
    # label's own set is what tells the client the edge is gone.
    # Deleting the message takes its edge with it, and what the delete recorded is the only thing that
    # tells the client the label's own set lost it.
    # The gap holds what the delete recorded, read the way a returning client's gap is.
    test "replays a gap holding a deleted row's edge by handing over its target without it" do
      %{label: label, message: message} = labelled_message()
      windows(%{@page => [@label_window]})
      hold_windows([@label_window])

      DB.delete!(message)

      # The round after the delete, which a running server makes for every write the window reads.
      Evaluator.round(@label_window, [])
      wait_until(fn -> ResultStore.versions(@label_window) != [] end)

      gap =
        0
        |> Oplog.read_after(0, 100)
        |> Enum.filter(&(&1.type == Module28 and &1.op in [:del_relationship, :del_entity]))

      start_session!(gap: gap)

      assert_receive {:sync_deltas, _cursor, deltas, _applied_seq}
      assert [%{data: data, op: :put_entity}] = Enum.filter(deltas, &(&1.id == label.id))
      assert data.messages == []
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

  # The fixture's named lines are limited to :name, so each deciding quantifier is answered under
  # the field's key as well as under the line's name.
  defp project_verdicts(archivable?) do
    Map.new(
      for name <- [:archive, :feature, :publish],
          key <- [name, {:update, :name}] do
        [%{predicates: [clause]}] = Policy.build(PolicyProject)[name]

        {Policy.verdict_key(PolicyProject, key, clause), name != :archive or archivable?}
      end
    )
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

  # An effect of this replica's batch with the given number on the given row, logged in the given
  # transaction - one above a batch's is what overtook it. Logged by hand: every write a test makes
  # is in the test's own transaction, so none can be above another.
  defp overtake(row, tx, seq) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash", "mutation_ref")
    VALUES ('patch_entity', $1, $2, $3::text::xid8, 'h', $4)
    """

    params = [
      Codec.encode_enum_value(row.__struct__),
      Codec.encode(row.id, :uuid),
      Integer.to_string(tx),
      %{"replica_id" => @replica_id, "seq" => seq}
    ]

    {:ok, _result} = Connection.query(statement, params)

    :ok
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
      synced_types: [PolicyModule1, PolicyProject],
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

  # A batch's part for the given project alone, carrying the given verdicts for it, read past the
  # session's edge.
  defp verdicts_part(project, verdicts) do
    place = {Oplog.current_xmax() + 1, 0}
    row = DB.read(PolicyProject, project.id)

    %{
      checked: %{PolicyProject => PackedIds.pack([project.id])},
      overtaking_seqs: %{},
      own_seqs: %{},
      pair_effects: %{},
      pairs: %{},
      place: place,
      readable: %{PolicyProject => %{project.id => row}},
      synced_types: [PolicyModule1, PolicyProject],
      tx_range: {elem(place, 0), elem(place, 0)},
      verdicts: %{PolicyProject => %{project.id => verdicts}},
      whole_types: [],
      written: %{}
    }
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
