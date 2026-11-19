defmodule Hologram.Sync.SessionTest do
  # async: false - each test writes the query cache's persistent term, shared by the whole node,
  # and starts the sync result store, the evaluator registry and the evaluators supervisor under
  # their registered names, which one test on the node can hold at a time.
  use Hologram.Test.DatabaseCase, async: false

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
  alias Hologram.DB.QueryCache
  alias Hologram.Entity
  alias Hologram.Mutation.Record
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Realtime.SSE
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Gate
  alias Hologram.Sync.Live
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.Pool
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Session
  alias Hologram.Sync.Sessions
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
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

  @board_window "w_board"
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

    wait_for_process_cleanup(Gate)
    start_supervised!(Gate)

    wait_for_process_cleanup(Sessions.registry())
    start_supervised!(Sessions)

    :ok
  end

  defp create(title) do
    %{a: true, c: title}
    |> Module2.new()
    |> DB.create!()
  end

  # One entry of what a returning client missed, in the shape the log reports it once the catch-up
  # has filled in its payload - the place included, since each chunk of the gap claims the place of
  # its last effect.
  defp logged(op, type, entity_id, data, place, mutation_ref \\ nil) do
    {tx, seq} = place

    %{
      actor_id: nil,
      data: data,
      entity_id: entity_id,
      model_hash: "h",
      mutation_ref: mutation_ref,
      old: nil,
      op: op,
      revisions: nil,
      seq: seq,
      tx: tx,
      type: type
    }
  end

  # Let into the sandbox, since the session reads the rows and the grant store itself to decide what
  # this client may see, so without this it judges every rule against the committed database rather
  # than against what the test wrote. Every reader lets the session in itself too, since both a fill
  # and a catch-up read in the continue that starts the session, before the test could.
  #
  # A test names what a returning client missed as `gap:`, and the edge the gap read reached as
  # `edge:` - the session reads both through `:read_gap`. The edge defaults to past the gap's last
  # transaction, so every chunk claims the place of its last effect.
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
      |> Keyword.put_new(:read_ids, read_ids_in_sandbox())
      |> Keyword.put_new(:read_part, read_part_in_sandbox())

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

  defp resume_opts(opts) do
    {gap, without_gap} = Keyword.pop(opts, :gap)
    {edge, session_opts} = Keyword.pop(without_gap, :edge)

    cond do
      gap ->
        edge = edge || edge_past(gap)

        Keyword.put(session_opts, :read_gap, fn -> {:ok, gap, edge} end)

      edge ->
        raise ArgumentError, "edge: names how far a gap's read reached, so it needs a gap:"

      true ->
        session_opts
    end
  end

  defp edge_past([]), do: 1

  defp edge_past(gap) do
    %{tx: tx} = List.last(gap)

    tx + 1
  end

  # A chunk of the gap judged for the session's user, by a session that lets itself into the
  # sandbox first and reads in the test's transaction, which is the one snapshot every read here
  # sees (see `read_fill_in_sandbox/4`).
  defp read_part_in_sandbox do
    test_pid = self()

    fn effects, actor_user_id, edges, synced_types, place, overtaken_above ->
      Process.flag(:trap_exit, true)
      allow_into_sandbox(self(), test_pid)

      Live.part_now(effects, actor_user_id, edges, synced_types, place, overtaken_above)
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

  describe "start_link/1 - coming back" do
    setup do
      user =
        %{email: "resumed@example.com"}
        |> Module14.new()
        |> DB.create!()

      windows(%{})

      %{user: user}
    end

    # What a returning client is taken to hold, given rather than read: a row the user could read
    # when the held ids were read, which the gap's chunk then finds gone.
    defp held_ids(held) do
      fn entity_type, _actor_user_id ->
        held
        |> Map.get(entity_type, [])
        |> PackedIds.pack()
      end
    end

    test "hands a row written several times while away over whole, once, as it stands" do
      renamed = create("renamed twice")

      gap = [
        logged(:patch_entity, Module2, renamed.id, %{"c" => "renamed once"}, {300, 1}),
        logged(:patch_entity, Module2, renamed.id, %{"c" => "renamed twice"}, {300, 2})
      ]

      start_session!(gap: gap)

      assert_receive {:sync_deltas, cursor, [%{data: data, id: id, op: :put_entity}], _seq}
      assert id == renamed.id
      assert data.c == "renamed twice"
      assert cursor == Cursor.encode(300, 2, @policy_hash, @types_hash)

      assert_receive {:sync_synced, :all, all_cursor}
      assert all_cursor == Cursor.encode(301, 0, @policy_hash, @types_hash)
      refute_received {:sync_deltas, _cursor, _deltas, _seq}
    end

    # The held ids are read after the grant, so the row is among them - and handed over whole all
    # the same, since the client may never have got it.
    test "hands over a row a grant given while away opens up", %{user: user} do
      opened = DB.create!(PolicyModule1.new())
      Auth.grant_role(user, :viewer, opened)

      grant = %{
        "entity_id" => opened.id,
        "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
        "id" => Entity.generate_id(),
        "role" => "viewer",
        "user_id" => user.id
      }

      start_session!(
        actor_user_id: user.id,
        gap: [logged(:put_entity, RoleGrant, grant["id"], grant, {300, 1})]
      )

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :put_entity}], _seq}
      assert id == opened.id

      assert_receive {:sync_synced, :all, _cursor}
    end

    test "drops a row it takes the client to hold that the user can no longer read" do
      gone = create("deleted while away")
      DB.delete!(gone)

      data = %{"a" => true, "b" => nil, "c" => "deleted while away", "id" => gone.id}

      start_session!(
        gap: [logged(:del_entity, Module2, gone.id, data, {300, 1})],
        read_ids: held_ids(%{Module2 => [gone.id]})
      )

      assert_receive {:sync_deltas, _cursor, deltas, _seq}
      assert deltas == [Frame.unsync_entity(gone.id, Module2)]
    end

    # The grant was revoked after the held ids were read, which held_ids/1 stands in for: the search
    # back from the grant's delete reaches the row, and the session takes the client to hold it.
    test "drops a held row a grant revoked while away hid", %{user: user} do
      hidden = DB.create!(PolicyModule1.new())

      grant = %{
        "entity_id" => hidden.id,
        "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
        "id" => Entity.generate_id(),
        "role" => "viewer",
        "user_id" => user.id
      }

      start_session!(
        actor_user_id: user.id,
        gap: [logged(:del_entity, RoleGrant, grant["id"], grant, {300, 1})],
        read_ids: held_ids(%{PolicyModule1 => [hidden.id]})
      )

      assert_receive {:sync_deltas, _cursor, deltas, _seq}
      assert deltas == [Frame.unsync_entity(hidden.id, PolicyModule1)]
    end

    test "tells a client that missed nothing that it holds everything, and nothing else" do
      create("unchanged")

      start_session!(gap: [])

      assert_receive {:sync_synced, :all, _cursor}
      refute_received {:sync_deltas, _cursor, _deltas, _seq}
    end

    test "tells the gap a chunk at a time, each dated by its last effect, a row in two chunks once" do
      put_app_env(:sync, rows_per_frame: 1)

      first = create("first")
      second = create("second")

      gap = [
        logged(:patch_entity, Module2, first.id, %{"c" => "first"}, {300, 1}),
        logged(:patch_entity, Module2, second.id, %{"c" => "second"}, {300, 2}),
        logged(:patch_entity, Module2, first.id, %{"c" => "first"}, {301, 3})
      ]

      start_session!(gap: gap)

      assert_receive {:sync_deltas, first_cursor, [%{id: first_id}], _seq}
      assert first_id == first.id
      assert first_cursor == Cursor.encode(300, 1, @policy_hash, @types_hash)

      assert_receive {:sync_deltas, second_cursor, [%{id: second_id}], _seq}
      assert second_id == second.id
      assert second_cursor == Cursor.encode(300, 2, @policy_hash, @types_hash)

      assert_receive {:sync_synced, :all, all_cursor}
      assert all_cursor == Cursor.encode(302, 0, @policy_hash, @types_hash)
      refute_received {:sync_deltas, _cursor, _deltas, _seq}
    end

    # A transaction below an effect the gap read returned can still have been open then.
    test "claims no place past the edge the gap read reached, and the marker claims the edge" do
      renamed = create("renamed")

      gap = [
        logged(:patch_entity, Module2, renamed.id, %{"c" => "renamed"}, {300, 1}),
        logged(:patch_entity, Module2, renamed.id, %{"c" => "renamed"}, {301, 2})
      ]

      start_session!(gap: gap, edge: 300)

      assert_receive {:sync_deltas, cursor, [%{id: _id}], _seq}
      assert cursor == Cursor.encode(300, 0, @policy_hash, @types_hash)

      assert_receive {:sync_synced, :all, all_cursor}
      assert all_cursor == Cursor.encode(300, 0, @policy_hash, @types_hash)
    end

    test "names this replica's number with the rows its batches in the gap wrote" do
      moved = create("moved while away")

      gap = [
        logged(:patch_entity, Module2, moved.id, %{"c" => "moved"}, {300, 1}, ref(@replica_id, 9))
      ]

      start_session!(applied_seq: 3, gap: gap, replica_id: @replica_id)

      assert_receive {:sync_deltas, _cursor, [%{id: _id}], 9}, 1_000
    end

    # The batch's transaction was open when the gap was read, below the gap's own, and committed
    # before the chunk's rows were read, which hold it.
    test "names this replica's batch the rows hold that committed below the gap's last effect" do
      moved = create("moved while away")
      overtake(moved, 250, 7)

      gap = [logged(:patch_entity, Module2, moved.id, %{"c" => "moved"}, {300, 1})]

      start_session!(applied_seq: 3, edge: 200, gap: gap, replica_id: @replica_id)

      assert_receive {:sync_deltas, _cursor, [%{id: id, op: :put_entity}], 7}
      assert id == moved.id
    end

    # One transaction can hold several of this replica's batches, and a chunk can end inside it.
    test "names this replica's batch in the chunk's last transaction that a later chunk holds" do
      put_app_env(:sync, rows_per_frame: 1)

      moved = create("moved while away")

      gap = [
        logged(:patch_entity, Module2, moved.id, %{"c" => "x"}, {300, 1}, ref(@replica_id, 4)),
        logged(:patch_entity, Module2, moved.id, %{"c" => "y"}, {300, 2}, ref(@replica_id, 5))
      ]

      overtake(moved, 300, 5)

      start_session!(applied_seq: 3, gap: gap, replica_id: @replica_id)

      assert_receive {:sync_deltas, _cursor, [%{id: _id, op: :put_entity}], 5}
    end

    test "joins the node's sessions before it reads what its user may read" do
      test_pid = self()
      read_ids = read_ids_in_sandbox()

      read_ids_joined = fn entity_type, actor_user_id ->
        send(test_pid, {:joined?, Enum.any?(Sessions.list(), &(elem(&1, 0) == self()))})

        read_ids.(entity_type, actor_user_id)
      end

      start_session!(gap: [], read_ids: read_ids_joined)

      assert_receive {:joined?, true}
      assert_receive {:sync_synced, :all, _cursor}
    end

    test "cuts the client off when the log says it has to be sent everything again" do
      session = start_session!(read_gap: fn -> {:full_resync, :gap_too_large} end)

      ref = Process.monitor(session)

      assert_receive {:DOWN, ^ref, :process, ^session, {:full_resync, :gap_too_large}}
      refute_received {:sync_synced, :all, _cursor}
    end

    # The batch is read while the gap is told, so it reaches the session before the catch-up is
    # over - and below the edge read after it, so it may be in some of what the catch-up read and
    # not in the rest.
    test "tells a batch routed during the catch-up after the marker, its rows whole" do
      task = create("before")
      test_pid = self()
      read_ids = read_ids_in_sandbox()

      read_ids_routing = fn entity_type, actor_user_id ->
        if entity_type == Module2 do
          send(test_pid, :reading)

          receive do
            :routed -> :ok
          end
        end

        read_ids.(entity_type, actor_user_id)
      end

      session = start_session!(gap: [], read_ids: read_ids_routing)

      assert_receive :reading, 1_000
      DB.update!(Module2, task.id, c: "after")
      route([live_effect(:patch_entity, Module2, task.id, %{"c" => "after"})], {1, 0})
      send(session, :routed)

      assert_receive {:sync_synced, :all, _cursor}, 1_000

      assert_receive {:sync_deltas, _cursor, [%{data: data, id: id, op: :put_entity}], _seq},
                     1_000

      assert id == task.id
      assert data.c == "after"
    end
  end

  describe "start_link/1 - sync's own pool" do
    # Read outside the test's sandbox, so the reader asks the connection who it is rather than
    # reading rows.
    test "reads a fill through sync's own pool when it is started" do
      put_app_env(:sync, pool_size: 1)
      start_supervised!(Pool.child_spec())

      windows(%{})
      test_pid = self()

      read_fill = fn _entity_type, _actor_user_id, _replica_id, _synced_types ->
        {:ok, %Postgrex.Result{rows: [[name]]}} =
          Connection.query("SELECT current_setting('application_name')")

        send(test_pid, {:read_on, name})

        {[], nil}
      end

      start_session!(read_fill: read_fill)

      assert_receive {:read_on, "hologram_sync"}, 1_000
      assert_receive {:sync_synced, :all, _cursor}, 1_000
    end

    # A grant moving a whole type under a connected client is what keeps it current, which a wave
    # filling on sync's pool mustn't hold up.
    test "reads a type again for a connected client on the app's pool" do
      put_app_env(:sync, pool_size: 1)
      start_supervised!(Pool.child_spec())

      windows(%{})
      test_pid = self()

      user =
        %{email: "connected@example.com"}
        |> Module14.new()
        |> DB.create!()

      read_fill = fn _entity_type, _actor_user_id, _replica_id, _synced_types ->
        {:ok, %Postgrex.Result{rows: [[name]]}} =
          Connection.query("SELECT current_setting('application_name')")

        send(test_pid, {:read_on, name})

        {[], nil}
      end

      session = start_session!(actor_user_id: user.id, read_fill: read_fill)

      assert_receive {:sync_synced, :all, _cursor}, 1_000
      flush_messages()

      grant = %{
        "entity_id" => nil,
        "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
        "id" => Entity.generate_id(),
        "role" => "viewer",
        "user_id" => user.id
      }

      effects = [logged(:put_entity, RoleGrant, grant["id"], grant, {300, 1})]
      synced_types = QueryCache.synced_types()
      part = Live.part_now(effects, user.id, Edges.index(), synced_types, {301, 0}, 300)

      assert PolicyModule1 in part.whole_types

      send(session, {:live, part})

      assert_receive {:read_on, name}, 1_000
      refute name == "hologram_sync"
    end

    test "reads a catch-up through sync's own pool when it is started" do
      put_app_env(:sync, pool_size: 1)
      start_supervised!(Pool.child_spec())

      windows(%{})
      test_pid = self()

      read_ids = fn _entity_type, _actor_user_id ->
        {:ok, %Postgrex.Result{rows: [[name]]}} =
          Connection.query("SELECT current_setting('application_name')")

        send(test_pid, {:read_on, name})

        ""
      end

      start_session!(gap: [], read_ids: read_ids)

      assert_receive {:read_on, "hologram_sync"}, 1_000
      assert_receive {:sync_synced, :all, _cursor}, 1_000
    end
  end

  describe "start_link/1 - coming back, at the gate" do
    setup do
      windows(%{})

      stop_supervised!(Gate)
      put_app_env(:sync, catchups_at_once: 1)
      start_supervised!(Gate)

      test_pid = self()

      holder =
        spawn_link(fn ->
          Gate.ask()

          receive do
            {:gate, :open} -> send(test_pid, :holding)
          end

          Process.sleep(:infinity)
        end)

      assert_receive :holding

      %{holder: holder}
    end

    defp registered?(session) do
      Enum.any?(Sessions.list(), &(elem(&1, 0) == session))
    end

    test "catches a client up only once the gate lets it in, and joins the sessions then", %{
      holder: holder
    } do
      session = start_session!(gap: [])
      :sys.get_state(session)

      refute registered?(session)
      refute_received {:sync_synced, :all, _cursor}

      Process.unlink(holder)
      Process.exit(holder, :kill)

      assert_receive {:sync_synced, :all, _cursor}, 1_000
      assert registered?(session)
    end

    test "leaves the gate once its client is caught up", %{holder: holder} do
      start_session!(gap: [])

      Process.unlink(holder)
      Process.exit(holder, :kill)

      assert_receive {:sync_synced, :all, _cursor}, 1_000

      wait_until(fn -> :sys.get_state(Gate).holders == %{} end)
    end

    test "stops when the gate goes while it waits" do
      session = start_session!(gap: [])
      :sys.get_state(session)
      ref = Process.monitor(session)

      stop_supervised!(Gate)

      assert_receive {:DOWN, ^ref, :process, ^session, {:shutdown, :gate_gone}}, 1_000
    end
  end

  describe "start_link/1 - coming back to rows lost before the held read" do
    setup do
      windows(%{})

      parent = DB.create!(PolicyModule1.new())

      child =
        [parent_id: parent.id]
        |> PolicyModule5.new()
        |> DB.create!()

      %{child: child, parent: parent}
    end

    # Every frame up to the marker saying the client holds everything, each as `{deltas, applied
    # seq}`.
    defp await_frames(acc \\ []) do
      receive do
        {:sync_deltas, _cursor, deltas, applied_seq} ->
          await_frames([{deltas, applied_seq} | acc])

        {:sync_synced, :all, _cursor} ->
          Enum.reverse(acc)
      after
        1_000 -> flunk("the client was never told it holds everything")
      end
    end

    # The rows the frames told by hash, per type, each checked against the hashes of the given
    # candidates.
    defp hashed(frames, candidates) do
      for {deltas, _seq} <- frames,
          %{data: %{hashes: hashes, salt: salt}, op: :unsync_hashed, type: type} <- deltas,
          hash <- hashes,
          id <- candidates,
          Frame.drop_hash(salt, id) == hash,
          do: {type, id}
    end

    test "drops by hash a row whose parent went private while away", %{
      child: child,
      parent: parent
    } do
      gap = [logged(:patch_entity, PolicyModule1, parent.id, %{"public" => false}, {300, 1})]

      start_session!(applied_seq: 3, gap: gap, replica_id: @replica_id)

      frames = await_frames()

      hashed_rows =
        frames
        |> hashed([child.id, parent.id])
        |> Enum.sort()

      assert hashed_rows == [
               {"Hologram.Test.Fixtures.Policy.Module1", parent.id},
               {"Hologram.Test.Fixtures.Policy.Module5", child.id}
             ]

      # No number: the client doesn't take a write of its own to a row whose set the drop changes
      # as being in what it holds.
      for {deltas, seq} <- frames, Enum.any?(deltas, &(&1.op == :unsync_hashed)) do
        assert seq == nil
      end

      refute Enum.any?(frames, fn {deltas, _seq} ->
               Enum.any?(deltas, &(&1.op == :unsync_entity))
             end)
    end

    # The batch is read after the gap, which holds nothing of it, and below the edge read once the
    # catch-up is over.
    test "drops by hash a row a batch routed during the catch-up hid", %{
      child: child,
      parent: parent
    } do
      DB.update!(PolicyModule1, parent.id, public: true)

      test_pid = self()
      read_ids = read_ids_in_sandbox()

      read_ids_routing = fn entity_type, actor_user_id ->
        if entity_type == Module2 do
          send(test_pid, :reading)

          receive do
            :routed -> :ok
          end
        end

        read_ids.(entity_type, actor_user_id)
      end

      session = start_session!(gap: [], read_ids: read_ids_routing)

      assert_receive :reading
      DB.update!(PolicyModule1, parent.id, public: false)
      route([live_effect(:patch_entity, PolicyModule1, parent.id, %{"public" => false})], {1, 0})
      send(session, :routed)

      assert_receive {:sync_synced, :all, _cursor}

      # The held ids of both types are read after the parent went private, so neither row is held:
      # the batch tells both by hash, each type in a frame of its own.
      assert_receive {:sync_deltas, _cursor, first, nil}
      assert_receive {:sync_deltas, _cursor, second, nil}

      hashed_rows =
        [{first, nil}, {second, nil}]
        |> hashed([child.id, parent.id])
        |> Enum.sort()

      assert hashed_rows == [
               {"Hologram.Test.Fixtures.Policy.Module1", parent.id},
               {"Hologram.Test.Fixtures.Policy.Module5", child.id}
             ]
    end

    # The chunk's search walks the tables as they stand once the child moved, so it no longer
    # reaches the child from the parent - and the move's own batch, routed meanwhile, finds the
    # child hidden and not held.
    test "drops by hash a row its parent's going private hid that then moved", %{
      child: child,
      parent: parent
    } do
      other_parent = DB.create!(PolicyModule1.new())
      read_part = read_part_in_sandbox()
      test_pid = self()

      read_part_after_move = fn effects, actor_user_id, edges, synced_types, place, above ->
        send(test_pid, :reading_chunk)

        receive do
          :moved -> :ok
        end

        read_part.(effects, actor_user_id, edges, synced_types, place, above)
      end

      gap = [logged(:patch_entity, PolicyModule1, parent.id, %{"public" => false}, {300, 1})]

      session = start_session!(gap: gap, read_part: read_part_after_move)

      assert_receive :reading_chunk
      DB.update!(PolicyModule5, child.id, parent_id: other_parent.id)

      moved = %{
        live_effect(:patch_entity, PolicyModule5, child.id, %{"parent_id" => other_parent.id})
        | old: %{"parent_id" => parent.id}
      }

      route([moved], {1, 0})
      send(session, :moved)

      chunk_frames = await_frames()

      assert hashed(chunk_frames, [child.id]) == []

      assert_receive {:sync_deltas, _cursor, deltas, nil}

      assert hashed([{deltas, nil}], [child.id]) == [
               {"Hologram.Test.Fixtures.Policy.Module5", child.id}
             ]
    end

    # Both chunks reach the rows the parent's going private hid, and the first settles them.
    test "drops by hash once a row two chunks of the gap reach", %{child: child, parent: parent} do
      put_app_env(:sync, rows_per_frame: 1)

      gap = [
        logged(:patch_entity, PolicyModule1, parent.id, %{"public" => false}, {300, 1}),
        logged(:patch_entity, PolicyModule1, parent.id, %{"public" => false}, {300, 2})
      ]

      start_session!(gap: gap)

      hashed_rows =
        await_frames()
        |> hashed([child.id, parent.id])
        |> Enum.sort()

      assert hashed_rows == [
               {"Hologram.Test.Fixtures.Policy.Module1", parent.id},
               {"Hologram.Test.Fixtures.Policy.Module5", child.id}
             ]
    end

    test "tells nothing of a row its user never could read whose rename is in the gap", %{
      parent: parent
    } do
      gap = [logged(:patch_entity, PolicyModule1, parent.id, %{"priority" => 5}, {300, 1})]

      start_session!(gap: gap)

      assert await_frames() == []
    end

    test "drops by hash, never by id, a row created and hidden in the gap" do
      created = DB.create!(PolicyModule1.new())
      data = %{"id" => created.id, "public" => false}

      start_session!(gap: [logged(:put_entity, PolicyModule1, created.id, data, {300, 1})])

      frames = await_frames()

      assert hashed(frames, [created.id]) == [
               {"Hologram.Test.Fixtures.Policy.Module1", created.id}
             ]

      refute Enum.any?(frames, fn {deltas, _seq} ->
               Enum.any?(deltas, &(&1.op == :unsync_entity))
             end)
    end
  end

  describe "start_link/1 - coming back to a type-wide grant" do
    setup do
      user =
        %{email: "resumed@example.com"}
        |> Module14.new()
        |> DB.create!()

      windows(%{})

      readable =
        [public: true]
        |> PolicyModule1.new()
        |> DB.create!()

      hidden = DB.create!(PolicyModule1.new())

      %{hidden: hidden, readable: readable, user: user}
    end

    # A grant's delete written to the log, where the session asks whether the gap took a grant of
    # its user's away - an entry of the gap naming it, at its place.
    defp logged_grant_delete(grant) do
      statement = """
      INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "data", "tx", "model_hash")
      VALUES ('del_entity', 'Hologram.Auth.RoleGrant', $1, $2, '300'::xid8, 'h')
      RETURNING "seq"
      """

      {:ok, %Postgrex.Result{rows: [[seq]]}} =
        Connection.query(statement, [Codec.encode(grant["id"], :uuid), grant])

      logged(:del_entity, RoleGrant, grant["id"], grant, {300, seq})
    end

    defp type_grant(user) do
      %{
        "entity_id" => nil,
        "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
        "id" => Entity.generate_id(),
        "role" => "viewer",
        "user_id" => user.id
      }
    end

    test "hands over every row of a type a grant given while away opens, once", %{
      hidden: hidden,
      readable: readable,
      user: user
    } do
      # A chunk per grant effect, each naming the type.
      put_app_env(:sync, rows_per_frame: 1)

      Auth.grant_role(user, :viewer, PolicyModule1)

      grant = type_grant(user)

      start_session!(
        actor_user_id: user.id,
        gap: [
          logged(:put_entity, RoleGrant, grant["id"], grant, {300, 1}),
          logged(:put_entity, RoleGrant, grant["id"], grant, {300, 2})
        ]
      )

      deltas = await_fill()

      put_ids =
        for %{op: :put_entity, type: "Hologram.Test.Fixtures.Policy.Module1", id: id} <- deltas,
            do: id

      assert Enum.sort(put_ids) == Enum.sort([readable.id, hidden.id])
      refute Enum.any?(deltas, &(&1.op == :keep_hashed))
    end

    test "tells the client which rows of a type to keep once a grant on all of it is gone", %{
      readable: readable,
      user: user
    } do
      grant = type_grant(user)

      start_session!(
        actor_user_id: user.id,
        gap: [logged_grant_delete(grant)]
      )

      frames = await_frames()

      keeps = for {deltas, _seq} <- frames, %{op: :keep_hashed} = keep <- deltas, do: keep
      kept_types = Enum.map(keeps, & &1.type)

      # The child reads through its parent, so the grant reached every row of it too.
      assert Enum.sort(kept_types) == [
               "Hologram.Test.Fixtures.Policy.Module1",
               "Hologram.Test.Fixtures.Policy.Module5"
             ]

      keep = Enum.find(keeps, &(&1.type == "Hologram.Test.Fixtures.Policy.Module1"))

      assert keep.data.hashes == [Frame.drop_hash(keep.data.salt, readable.id)]

      for {deltas, seq} <- frames, Enum.any?(deltas, &(&1.op == :keep_hashed)) do
        assert seq == nil
      end
    end

    # A grant's id is worked out from who holds which role on what, so a client could hash its
    # guesses - grants go out as the list the client may keep instead.
    test "tells grants the user may not read by a keep list, never by hash", %{user: user} do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: false,
        synced_types: [Module2, PolicyModule1, PolicyModule5, RoleGrant],
        windows: %{}
      })

      other =
        %{email: "other@example.com"}
        |> Module14.new()
        |> DB.create!()

      third =
        %{email: "third@example.com"}
        |> Module14.new()
        |> DB.create!()

      Auth.grant_role(user, :viewer, PolicyModule1)
      Auth.grant_role(other, :viewer, PolicyModule1)
      Auth.grant_role(third, :viewer, PolicyModule1)

      grants = DB.read(RoleGrant)
      own_grant = Enum.find(grants, &(&1.user_id == user.id))

      [first_hidden, second_hidden] =
        Enum.map([other, third], fn holder ->
          grant = Enum.find(grants, &(&1.user_id == holder.id))

          data = %{
            "entity_id" => nil,
            "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
            "id" => grant.id,
            "role" => "viewer",
            "user_id" => holder.id
          }

          {grant.id, data}
        end)

      # Two chunks, each hiding another user's grant: the list goes out once.
      put_app_env(:sync, rows_per_frame: 1)

      start_session!(
        actor_user_id: user.id,
        gap: [
          logged(:put_entity, RoleGrant, elem(first_hidden, 0), elem(first_hidden, 1), {300, 1}),
          logged(:put_entity, RoleGrant, elem(second_hidden, 0), elem(second_hidden, 1), {300, 2})
        ]
      )

      frames = await_frames()
      deltas = Enum.flat_map(frames, fn {deltas, _seq} -> deltas end)

      refute Enum.any?(
               deltas,
               &(&1.op == :unsync_hashed and &1.type == "Hologram.Auth.RoleGrant")
             )

      assert [keep] =
               Enum.filter(
                 deltas,
                 &(&1.op == :keep_hashed and &1.type == "Hologram.Auth.RoleGrant")
               )

      assert keep.data.hashes == [Frame.drop_hash(keep.data.salt, own_grant.id)]
    end

    # The second read of what the user may read of grants stands for one made after the held ids
    # were read - a grant the user's own write created meanwhile, say - which no part has told.
    test "keeps the grants its user may read when the list is read, and drops one by id once hidden",
         %{user: user} do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: false,
        synced_types: [Module2, PolicyModule1, PolicyModule5, RoleGrant],
        windows: %{}
      })

      other =
        %{email: "other@example.com"}
        |> Module14.new()
        |> DB.create!()

      Auth.grant_role(other, :viewer, PolicyModule1)

      other_grant =
        RoleGrant
        |> DB.read()
        |> Enum.find(&(&1.user_id == other.id))

      made_meanwhile = Entity.generate_id()

      grant_data = fn id, holder_id ->
        %{
          "entity_id" => nil,
          "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
          "id" => id,
          "role" => "viewer",
          "user_id" => holder_id
        }
      end

      read_ids = read_ids_in_sandbox()
      reads = :counters.new(1, [])

      read_ids_twice = fn entity_type, actor_user_id ->
        if entity_type == RoleGrant do
          :counters.add(reads, 1, 1)

          if :counters.get(reads, 1) > 1,
            do: PackedIds.pack([made_meanwhile]),
            else: PackedIds.pack([])
        else
          read_ids.(entity_type, actor_user_id)
        end
      end

      put_app_env(:sync, rows_per_frame: 1)

      start_session!(
        actor_user_id: user.id,
        gap: [
          logged(
            :put_entity,
            RoleGrant,
            other_grant.id,
            grant_data.(other_grant.id, other.id),
            {300, 1}
          ),
          logged(
            :del_entity,
            RoleGrant,
            made_meanwhile,
            grant_data.(made_meanwhile, user.id),
            {300, 2}
          )
        ],
        read_ids: read_ids_twice
      )

      deltas = Enum.flat_map(await_frames(), fn {deltas, _seq} -> deltas end)

      assert [keep] =
               Enum.filter(
                 deltas,
                 &(&1.op == :keep_hashed and &1.type == "Hologram.Auth.RoleGrant")
               )

      assert keep.data.hashes == [Frame.drop_hash(keep.data.salt, made_meanwhile)]
      assert Frame.unsync_entity(made_meanwhile, RoleGrant) in deltas
    end

    test "tells no keep list once a grant of another user's on all of a type is gone", %{
      user: user
    } do
      other =
        %{email: "other@example.com"}
        |> Module14.new()
        |> DB.create!()

      grant = type_grant(other)

      start_session!(
        actor_user_id: user.id,
        gap: [logged_grant_delete(grant)]
      )

      refute Enum.any?(await_frames(), fn {deltas, _seq} ->
               Enum.any?(deltas, &(&1.op == :keep_hashed))
             end)
    end

    # The reread hands every row of the type over, so a later chunk writing one of them sends it no
    # second time.
    test "hands a row of a type read again whole over once, whatever later chunks write", %{
      hidden: hidden,
      readable: readable,
      user: user
    } do
      put_app_env(:sync, rows_per_frame: 1)

      Auth.grant_role(user, :viewer, PolicyModule1)

      grant = type_grant(user)

      start_session!(
        actor_user_id: user.id,
        gap: [
          logged(:put_entity, RoleGrant, grant["id"], grant, {300, 1}),
          logged(:patch_entity, PolicyModule1, hidden.id, %{"priority" => 4}, {300, 2})
        ]
      )

      put_ids =
        for %{op: :put_entity, type: "Hologram.Test.Fixtures.Policy.Module1", id: id} <-
              await_fill(),
            do: id

      assert Enum.sort(put_ids) == Enum.sort([readable.id, hidden.id])
    end
  end

  describe "start_link/1 - coming back to sets" do
    setup do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        permission_checking?: false,
        synced_types: [PolicyModule1, PolicyParent],
        windows: %{}
      })

      windows(%{})

      parent = DB.create!(PolicyParent.new())

      [kept, added] =
        Enum.map(1..2, fn _index ->
          [public: true]
          |> PolicyModule1.new()
          |> DB.create!()
        end)

      %{added: added, kept: kept, parent: parent}
    end

    defp pair_effect(op, parent, child, place) do
      data = %{"relationship" => "children", "target_id" => child.id}

      logged(op, PolicyParent, parent.id, data, place)
    end

    test "states the set a pair added while away changed", %{
      added: added,
      kept: kept,
      parent: parent
    } do
      :ok = EntityOperations.add_relationship(PolicyParent, parent.id, :children, kept.id)
      :ok = EntityOperations.add_relationship(PolicyParent, parent.id, :children, added.id)

      start_session!(gap: [pair_effect(:add_relationship, parent, added, {300, 1})])

      deltas = await_fill()

      assert %{data: data} = Enum.find(deltas, &(&1.id == parent.id))
      assert Enum.sort(data.children) == Enum.sort([kept.id, added.id])
    end

    test "states the set a pair removed while away changed", %{kept: kept, parent: parent} do
      :ok = EntityOperations.add_relationship(PolicyParent, parent.id, :children, kept.id)

      removed =
        [public: true]
        |> PolicyModule1.new()
        |> DB.create!()

      start_session!(gap: [pair_effect(:del_relationship, parent, removed, {300, 1})])

      deltas = await_fill()

      assert %{data: data} = Enum.find(deltas, &(&1.id == parent.id))
      assert data.children == [kept.id]
    end

    # A frame carries at most one row here, and the pair hands over both of its ends.
    test "dates only the last frame of a chunk split across frames", %{
      added: added,
      parent: parent
    } do
      put_app_env(:sync, rows_per_frame: 1)

      :ok = EntityOperations.add_relationship(PolicyParent, parent.id, :children, added.id)

      start_session!(gap: [pair_effect(:add_relationship, parent, added, {300, 1})])

      assert_receive {:sync_deltas, first_cursor, [_first], _seq}
      assert first_cursor == nil

      assert_receive {:sync_deltas, last_cursor, [_last], _seq}
      assert last_cursor == Cursor.encode(300, 1, @policy_hash, @types_hash)
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

      start_session!(fill_place: {200, 0}, gap: [], edge: 200)

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

      assert_receive {:sync_deltas, _cursor, _deltas, 5}, 1_000

      DB.update!(Module2, task.id, c: "again")

      route([
        live_effect(:patch_entity, Module2, task.id, %{"c" => "again"}, ref(@replica_id, 2))
      ])

      assert_receive {:sync_deltas, _cursor, _deltas, 5}, 1_000
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

      assert_receive {:DOWN, ^ref, :process, ^session, {:shutdown, :model_held}}, 1_000
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
          state: %{}
        })

      assert status.message == {:live, :redacted}
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

  # Drops what the session sent so far, so a test reads only what follows.
  defp flush_messages do
    receive do
      _message -> flush_messages()
    after
      0 -> :ok
    end
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
