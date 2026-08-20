defmodule Hologram.Migration.TailBuildTest do
  # The applier's TAIL: the index builds a migration file cannot carry inside its own
  # transaction, because the table already holds rows and PostgreSQL forbids a concurrent
  # build in a transaction. They run after the file commits, which puts them outside every
  # guarantee the file itself has.
  #
  # They run under the builder lock, and that is the whole of what this pins. Without it,
  # a node that finds the chain applied reaches its own repair while this build is still in
  # flight, reads the half-built index as broken - a concurrent build registers its index
  # invalid from the moment it starts - and rebuilds it. Two concurrent builds on one
  # relation, each waiting on the other's virtual transaction. The lock is also the only
  # signal that tells in-progress work apart from abandoned work.
  #
  # The fix shipped with no test of its own (step 07, entry 47), naming this tier as where
  # it becomes testable: the sandbox cannot run a concurrent build at all, and the cluster
  # suite reaches the race only when two peers happen to arrive together - which it did
  # twice, both times after days of looking like a flake.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # Derived for the relationship the second file adds. Its table is created by the FIRST
  # file, which is what sends this build to the tail rather than into the transaction.
  @index "my_app_task_author_id_$idx"

  # The value of Hologram.Migrator's @index_advisory_lock_key, hardcoded for the same
  # reason as in the contention suite: the key is frozen, so a test that followed a change
  # to it would hide what it exists to catch.
  @index_lock_key 6_059_159_047_318_510_073

  # Hologram.Migrator's @index_repair_poll_interval_ms - the cadence the tail retries at.
  @poll_interval_ms 1_000

  defp await_version_recorded(session, version) do
    # The file commits within milliseconds of the applier starting. This loop guards
    # against a hung test rather than tuning anything, so reaching its end is a failure.
    await_version_recorded(session, version, 200)
  end

  defp await_version_recorded(_session, version, 0) do
    flunk("migration #{version} was never recorded")
  end

  defp await_version_recorded(session, version, attempts_left) do
    statement = ~s{SELECT COUNT(*) FROM "hologram_system"."migration" WHERE "version" = $1}

    # The system tables do not exist until the applier claims the database, so an error
    # here means "not yet" rather than a failure.
    case Postgrex.query(session, statement, [version]) do
      {:ok, %{rows: [[1]]}} ->
        :ok

      _not_yet ->
        Process.sleep(25)
        await_version_recorded(session, version, attempts_left - 1)
    end
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

  setup %{scratch_opts: scratch_opts} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4}
      ])

    # my_app_task already stands when this file runs, so its index cannot be built inside
    # the file's transaction - the renderer puts it in the tail and stamps it concurrent.
    relate =
      migration("20260813142237", [
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :author,
          type: MyApp.User,
          opts: [optional: true],
          line: 3
        }
      ])

    first_model = Model.fold(Model.empty(), create.ops)
    full_model = Model.fold(first_model, relate.ops)

    observer = start_supervised!({Postgrex, scratch_opts}, id: :observer)

    [chain: [create, relate], full_model: full_model, observer: observer]
  end

  describe "run/3" do
    test "waits for the builder lock before building the tail's index", %{
      chain: chain,
      full_model: full_model,
      observer: observer,
      scratch_opts: scratch_opts
    } do
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      # Another node is building something. This one must not build alongside it.
      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@index_lock_key])

      applier =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> run(chain, full_model, @context) end)
        end)

      # The file itself is done - it committed, and its version is recorded. Everything
      # after this point is the tail.
      await_version_recorded(observer, "20260813142237")

      Process.sleep(2 * @poll_interval_ms)

      # The deploy is held here, and that is correct: the index is the last thing it owes,
      # and it may not build while another node might be building the same one. Before the
      # tail took this lock, the build ran the moment the file committed - so both of these
      # assertions are the fix, stated.
      assert Task.yield(applier, 0) == nil
      assert index_validity(observer) == :absent

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@index_lock_key])

      assert Task.await(applier, 30_000) == :ok
      assert index_validity(observer) == true

      # The tail let the lock go, so the next node is not stranded behind a finished build.
      assert %{rows: [[true]]} =
               Postgrex.query!(observer, "SELECT pg_try_advisory_lock($1)", [@index_lock_key])
    end
  end
end
