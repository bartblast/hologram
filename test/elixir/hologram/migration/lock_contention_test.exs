defmodule Hologram.Migration.LockContentionTest do
  # What a node does when another node already holds the migration lock. The answer the
  # migrator gives - poll, never queue - is not a politeness choice but the only one that
  # terminates, and this is where that is provable.
  #
  # The cycle it avoids: a concurrent index build waits for every transaction whose snapshot
  # predates its validation pass, and a session queued on pg_advisory_lock is exactly that -
  # a blocked statement holds its snapshot and its virtual transaction for as long as it
  # waits. So a node that queues waits for the builder, and the builder waits for the queued
  # node. Each holds what the other needs.
  #
  # Reproducing it takes a build IN FLIGHT, which is why a test that only parks the lock
  # proves nothing: with no build running, a queued waiter simply gets the lock when the
  # holder lets go, and passes just as happily against the code that deadlocked in
  # production. The build is held in flight here by a third session whose open transaction
  # the build has to wait out.
  #
  # The last test is issue #1077 itself, and it is the one the two keys could not survive.
  # Before the fix the appliers had a key of their own, so a node with a pending file took it
  # while another node's index build was mid-flight, opened its transaction, and asked for
  # the table lock the build was holding - AccessExclusiveLock against a concurrent build,
  # with the build already waiting on that transaction's snapshot. One key for the whole
  # procedure is what removes the overlap: the second node cannot open its transaction at all
  # until the first has finished building.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  @index "my_app_task_title_$sort_$idx"

  @index_op %{
    op: :create_index,
    table: "my_app_task",
    index: @index,
    columns: ["title_$sort"],
    nulls_distinct: true,
    unique: false
  }

  # The value of Hologram.Migrator's @advisory_lock_key - the one key the whole procedure
  # runs under. Hardcoded rather than read: the key is frozen forever - a different one
  # breaks mutual exclusion across Hologram versions - so a test that followed a change to it
  # would hide exactly what it must catch.
  @migration_lock_key -335_777_576_117_788_795

  # Hologram.Migrator's @migration_lock_poll_interval_ms. Mirrored for the same reason, and
  # used only to size waits in terms of the loop's own cadence.
  @poll_interval_ms 1_000

  defp await_waiting_build(session) do
    # The build blocks at its first wait phase, which it reaches at once. This loop is a
    # guard against a hung test rather than a tuning knob - reaching its end is a failure,
    # never a fallback, so the cap is deliberately far above the wait it covers.
    await_waiting_build(session, 100)
  end

  defp await_waiting_build(_session, 0) do
    flunk("the concurrent build never began waiting")
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
  # Sessions parked on a TABLE lock. This is what a node that opened its transaction while
  # another node's build was running looks like, and it is the state the one key exists to
  # make unreachable - the deadlock is that session waiting for the build while the build
  # waits for its snapshot. A node waiting for the migration lock is between statements and
  # does not appear here at all, which is the whole difference and is invisible to a "has the
  # task finished yet" assertion: polling and parked-on-a-lock both answer "not yet".
  #
  # The build itself waits as Lock/virtualxid rather than Lock/relation, so it is not counted.
  defp blocked_on_relation_count(session) do
    statement = """
    SELECT COUNT(*) FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "wait_event_type" = 'Lock'
      AND "wait_event" = 'relation' AND "pid" <> pg_backend_pid()
    """

    %{rows: [[count]]} = Postgrex.query!(session, statement, [])

    count
  end

  defp build_states(session) do
    statement = """
    SELECT left("query", 6), COALESCE("wait_event_type", 'none')
    FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "query" LIKE 'CREATE%INDEX CONCURRENTLY%'
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

  defp not_null?(session) do
    statement = """
    SELECT a."attnotnull"
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a."attrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND c."relname" = 'my_app_task' AND a."attname" = 'title'
    """

    %{rows: [[not_null?]]} = Postgrex.query!(session, statement, [])

    not_null?
  end

  # A session waiting for an advisory lock, which is the shape the deadlock is made of.
  #
  # Scoped to this database the way build_states/1 above is: pg_locks is CLUSTER-wide, and an
  # advisory lock records the database its session took it in - so an unscoped count would read
  # every database on the server and answer for sessions this test has nothing to do with.
  defp queued_advisory_lock_count(session) do
    statement = """
    SELECT COUNT(*) FROM pg_catalog.pg_locks
    WHERE "locktype" = 'advisory' AND NOT "granted"
      AND "database" = (
        SELECT "oid" FROM pg_catalog.pg_database WHERE "datname" = current_database()
      )
    """

    %{rows: [[count]]} = Postgrex.query!(session, statement, [])

    count
  end

  # A deploy on a session of its own, the way another node would run it. The session is
  # routed so that the procedure's own lock connection follows it to this database.
  defp start_run(chain, model, scratch_opts) do
    Task.async(fn ->
      {:ok, session} = Postgrex.start_link(scratch_opts)

      route(session, fn -> run(chain, model, @context) end)
    end)
  end

  setup %{scratch: scratch, scratch_opts: scratch_opts} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [optional: true],
          line: 4
        }
      ])

    # The file that changes the table underneath a build: ALTER TABLE ... SET NOT NULL takes
    # AccessExclusiveLock on my_app_task, which is the lock a concurrent build on that table
    # will not yield.
    tighten =
      migration("20260813142237", [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [optional: false],
          line: 3
        }
      ])

    first_model = Model.fold(Model.empty(), create.ops)
    full_model = Model.fold(first_model, tighten.ops)

    # The index is dropped so a build has real work to do, and because the model still
    # declares it, the database is back to matching the model once that build finishes.
    route(scratch, fn ->
      :ok = run([create], first_model, @context)

      # Rows, because a build over an empty table finishes between two statements - too fast
      # for a second node to still be inside its own transaction when the build validates,
      # which is the overlap every test here is about. This is also why a tail build exists
      # at all: an index on a table that already carries rows cannot ride its file's
      # transaction.
      {:ok, _result} =
        Connection.query("""
        INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at", "$revisions")
        SELECT gen_random_uuid(), 'task ' || g, now(), now(), '{}' FROM generate_series(1, 200000) g
        """)

      {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{@index}"})
    end)

    observer = start_supervised!({Postgrex, scratch_opts}, id: :observer)

    [
      chain: [create, tighten],
      first_model: first_model,
      full_model: full_model,
      observer: observer
    ]
  end

  describe "run/3" do
    test "polls rather than queues while another node's build is in flight", %{
      chain: chain,
      full_model: full_model,
      observer: observer,
      scratch_opts: scratch_opts
    } do
      blocker = start_supervised!({Postgrex, scratch_opts}, id: :blocker)
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      # An open transaction holding a lock on the table - what a concurrent build has to
      # wait out, and so what keeps the build in flight for as long as the test needs.
      Postgrex.query!(blocker, "BEGIN", [])
      Postgrex.query!(blocker, ~s{SELECT COUNT(*) FROM "hologram_data"."my_app_task"}, [])

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      build =
        Task.async(fn ->
          Postgrex.query!(holder, concurrent_build_statement(), [], timeout: :infinity)
        end)

      await_waiting_build(observer)

      deploy = start_run(chain, full_model, scratch_opts)

      # Two of the poll loop's own rounds, so it has certainly reached the lock and been
      # refused it at least once.
      Process.sleep(2 * @poll_interval_ms)

      # The claim, observed directly rather than inferred from the outcome: no session is
      # QUEUED on an advisory lock. A node that waited on the lock would sit here holding a
      # snapshot and a virtual transaction, and the build - which waits for exactly those -
      # would never finish. It polls instead, so it is between statements, holding nothing.
      assert queued_advisory_lock_count(observer) == 0
      assert blocked_on_relation_count(observer) == 0
      assert Task.yield(deploy, 0) == nil

      Postgrex.query!(blocker, "COMMIT", [])

      assert %Postgrex.Result{} = Task.await(build, 30_000)

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      assert Task.await(deploy, 30_000) == :ok
      assert index_validity(observer) == true
    end

    test "takes over when the lock holder's session dies", %{
      chain: chain,
      full_model: full_model,
      observer: observer,
      scratch_opts: scratch_opts
    } do
      # Temporary, so stopping it below is final - a permanent child would be restarted,
      # which would say nothing about a node that is gone for good.
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder, restart: :temporary)

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      deploy = start_run(chain, full_model, scratch_opts)

      Process.sleep(2 * @poll_interval_ms)

      # Nothing to do but wait: the lock is held, and the node holding it has done none of
      # the work. A deploy that gave up here would leave the fleet without its index.
      assert Task.yield(deploy, 0) == nil
      assert index_validity(observer) == :absent

      # The holder does not release the lock - its session ends, which is what a killed
      # node does. An advisory lock lives on its session, so it goes with it.
      stop_supervised!(:holder)

      # The next poll finds the lock free and does the work itself.
      assert Task.await(deploy, 30_000) == :ok
      assert index_validity(observer) == true

      # And it let go of what it took: a lock left held would strand the next node exactly
      # as the dead one nearly did.
      assert %{rows: [[true]]} =
               Postgrex.query!(observer, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])
    end

    test "applies a schema change without deadlocking a build in flight", %{
      chain: chain,
      full_model: full_model,
      observer: observer,
      scratch_opts: scratch_opts
    } do
      blocker = start_supervised!({Postgrex, scratch_opts}, id: :blocker)
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      Postgrex.query!(blocker, "BEGIN", [])
      Postgrex.query!(blocker, ~s{SELECT COUNT(*) FROM "hologram_data"."my_app_task"}, [])

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      build =
        Task.async(fn ->
          Postgrex.query!(holder, concurrent_build_statement(), [], timeout: :infinity)
        end)

      await_waiting_build(observer)

      # This node has a file PENDING, and that file's ALTER TABLE wants the very table the
      # build is holding. Before the fix it took a key of its own, opened its transaction and
      # asked for AccessExclusiveLock here, which is the deadlock: the build was already
      # waiting on this transaction's snapshot.
      deploy = start_run(chain, full_model, scratch_opts)

      Process.sleep(2 * @poll_interval_ms)

      assert queued_advisory_lock_count(observer) == 0
      assert Task.yield(deploy, 0) == nil

      # The claim itself: this node has not opened a transaction against the table at all.
      # Without it "the task has not finished" would pass just as happily against a node
      # parked on the table lock, which is the deadlock's own half of the cycle.
      assert blocked_on_relation_count(observer) == 0

      # And nothing of the pending file reached the database while the build was running.
      assert not_null?(observer) == false

      Postgrex.query!(blocker, "COMMIT", [])

      assert %Postgrex.Result{} = Task.await(build, 30_000)

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      # Both finish, neither raises. A deadlock here would have come back as a Postgrex.Error
      # carrying pg_code 40P01, taking the node's boot down with it.
      assert Task.await(deploy, 30_000) == :ok
      assert not_null?(observer) == true
      assert index_validity(observer) == true
    end
  end
end
