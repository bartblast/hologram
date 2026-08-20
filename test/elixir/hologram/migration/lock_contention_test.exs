defmodule Hologram.Migration.LockContentionTest do
  # What a node does when another node already holds the index builder lock. The answer the
  # migrator gives - poll the catalog, never queue on the lock - is not a politeness choice
  # but the only one that terminates, and this is where that is provable.
  #
  # The cycle it avoids: a concurrent build waits for every transaction that could see its
  # table, and a session queued on pg_advisory_lock IS one - a blocked statement holds a
  # virtual transaction for as long as it waits. So a node that queues waits for the
  # builder, and the builder waits for the queued node. Each holds what the other needs.
  #
  # Reproducing it takes a build IN FLIGHT, which is why a test that only parks the lock
  # proves nothing: with no build running, a queued waiter simply gets the lock when the
  # holder lets go, and passes just as happily against the code that deadlocked in
  # production. The build is held in flight here by a third session whose open transaction
  # the build has to wait out.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  @index "hologram_role_grant_$uidx"

  @index_op %{
    op: :create_index,
    table: "hologram_role_grant",
    index: @index,
    columns: ["user_id", "resource_type", "resource_id", "role"],
    nulls_distinct: false,
    unique: true
  }

  # The value of Hologram.Migrator's @index_advisory_lock_key. Hardcoded rather than read:
  # the key is frozen forever - a different one breaks mutual exclusion across Hologram
  # versions - so a test that follows a change to it would hide exactly what it must catch.
  @index_lock_key 6_059_159_047_318_510_073

  # Hologram.Migrator's @index_repair_poll_interval_ms. Mirrored for the same reason, and
  # used only to size waits in terms of the loop's own cadence.
  @poll_interval_ms 1_000

  defp await_waiting_build(session) do
    # The build blocks at its first wait phase, which it reaches at once. This loop is a
    # guard against a hung test rather than a tuning knob - reaching its end is a failure,
    # never a fallback, so the cap is deliberately far above the wait it covers.
    await_waiting_build(session, 100)
  end

  defp await_waiting_build(session, 0) do
    flunk("the concurrent build never began waiting: #{inspect(build_states(session))}")
  end

  defp await_waiting_build(session, attempts_left) do
    if build_states(session) == [{"CREATE", "Lock"}] do
      :ok
    else
      Process.sleep(50)
      await_waiting_build(session, attempts_left - 1)
    end
  end

  # What every concurrent build on this database is doing, as {statement kind, what it
  # waits on} - "Lock" is the build parked behind another session's transaction.
  defp build_states(session) do
    statement = """
    SELECT left("query", 6), COALESCE("wait_event_type", 'none')
    FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "query" LIKE 'CREATE UNIQUE INDEX CONCURRENTLY%'
    """

    %{rows: rows} = Postgrex.query!(session, statement, [])

    Enum.map(rows, fn [kind, wait_event_type] -> {kind, wait_event_type} end)
  end

  defp concurrent_build_statement do
    concurrent_op = Map.put(@index_op, :concurrently, true)
    [statement] = DDL.statements(concurrent_op)

    statement
  end

  defp index_validity(session) do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Postgrex.query!(session, statement, [@index]) do
      %{rows: [[valid?]]} -> valid?
      %{rows: []} -> :absent
    end
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  # A session waiting for an advisory lock, which is the shape the deadlock is made of.
  defp queued_advisory_lock_count(session) do
    statement = """
    SELECT COUNT(*) FROM pg_catalog.pg_locks
    WHERE "locktype" = 'advisory' AND NOT "granted"
    """

    %{rows: [[count]]} = Postgrex.query!(session, statement, [])

    count
  end

  setup %{scratch: scratch, scratch_opts: scratch_opts} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4},
        %{op: :add_role, entity: MyApp.Task, name: :editor, opts: [], line: 5},
        %{op: :designate_user_entity, entity: MyApp.User, line: 6}
      ])

    model = Model.fold(Model.empty(), create.ops)

    # The index is dropped so a repair has real work to find, which is what sends it to the
    # lock in the first place.
    route(scratch, fn ->
      :ok = run([create], model, @context)

      {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{@index}"})
    end)

    observer = start_supervised!({Postgrex, scratch_opts}, id: :observer)

    [mapping: Mapper.derive_from_model!(model), observer: observer]
  end

  describe "repair_indexes/1" do
    test "polls rather than queues while another node's build is in flight", %{
      mapping: mapping,
      observer: observer,
      scratch_opts: scratch_opts
    } do
      blocker = start_supervised!({Postgrex, scratch_opts}, id: :blocker)
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      # An open transaction holding a lock on the table - what a concurrent build has to
      # wait out, and so what keeps the build in flight for as long as the test needs.
      Postgrex.query!(blocker, "BEGIN", [])

      Postgrex.query!(
        blocker,
        ~s{SELECT COUNT(*) FROM "hologram_data"."hologram_role_grant"},
        []
      )

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@index_lock_key])

      build =
        Task.async(fn ->
          Postgrex.query!(holder, concurrent_build_statement(), [], timeout: :infinity)
        end)

      await_waiting_build(observer)

      repair =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> repair_indexes(mapping) end)
        end)

      # Two of the repair loop's own rounds, so it has certainly reached the lock and been
      # refused it at least once.
      Process.sleep(2 * @poll_interval_ms)

      # The claim, observed directly rather than inferred from the outcome: no session is
      # QUEUED on an advisory lock. A repair that waited on the lock would sit here holding
      # a virtual transaction, and the build - which waits for exactly those - would never
      # finish. It polls instead, so it is between statements, holding nothing.
      assert queued_advisory_lock_count(observer) == 0
      assert Task.yield(repair, 0) == nil

      Postgrex.query!(blocker, "COMMIT", [])

      assert %Postgrex.Result{} = Task.await(build, 30_000)

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@index_lock_key])

      # The repair leaves through its work-done branch: the index it was going to build is
      # there, built by the node that held the lock.
      assert Task.await(repair, 30_000) == :ok
      assert index_validity(observer) == true
    end
  end
end
