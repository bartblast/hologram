defmodule Hologram.Migration.TailBuildTest do
  # The applier's TAIL: the index builds a migration file cannot carry inside its own
  # transaction, because PostgreSQL forbids a concurrent build in a transaction. They run
  # after the file commits, which puts them outside every guarantee the file itself has.
  #
  # What this pins is where the tail now sits. It used to be the ONLY gated part of the
  # procedure - the files applied under a key of their own and released it at each commit,
  # and the tail then took a second key of its own to build under. That gap between the two
  # was issue #1077: another node took the applier key the moment a file committed and ran
  # the next file's ALTER TABLE straight into the build this one had just started.
  #
  # One key covers the whole procedure now, so the gate is not around the tail but around
  # everything: a node that cannot have the key has not claimed the database, has not applied
  # a file, and has not begun a build. The tail rides inside that, on the session already
  # holding the key, which by then has no open transaction - which is exactly what a
  # concurrent build needs.
  #
  # Entry 47's fix shipped with no test of its own, naming this tier as where it becomes
  # testable: the sandbox cannot run a concurrent build at all, and the cluster suite reaches
  # the race only when two peers happen to arrive together - which it did twice, both times
  # after days of looking like a flake.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
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

  # The value of Hologram.Migrator's @advisory_lock_key, hardcoded for the same reason as in
  # the contention suite: the key is frozen, so a test that followed a change to it would
  # hide what it exists to catch.
  @migration_lock_key -335_777_576_117_788_795

  # Hologram.Migrator's @migration_lock_poll_interval_ms - the cadence a waiting node retries
  # at.
  @poll_interval_ms 1_000

  defp applied_versions_of(session) do
    statement = ~s{SELECT "version" FROM "hologram_system"."migration" ORDER BY "version"}

    %{rows: rows} = Postgrex.query!(session, statement, [])

    Enum.map(rows, fn [version] -> version end)
  end

  # Whether the database has been claimed at all. The system tables do not exist until the
  # guard creates them, so this is the earliest observable step of the whole procedure - and
  # therefore what proves a waiting node has not started rather than merely not finished.
  defp hologram_schema_count(session) do
    statement = """
    SELECT COUNT(*)
    FROM pg_catalog.pg_namespace
    WHERE "nspname" IN ('hologram_data', 'hologram_system')
    """

    %{rows: [[count]]} = Postgrex.query!(session, statement, [])

    count
  end

  # Unique beside valid, because a declaration-derived unique index has two things to prove:
  # that PostgreSQL enforces it at all, and that its concurrent build finished.
  defp index_flags(session, index \\ @index) do
    statement = """
    SELECT i."indisunique", i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Postgrex.query!(session, statement, [index]) do
      %{rows: [[unique?, valid?]]} -> %{unique: unique?, valid: valid?}
      %{rows: []} -> :absent
    end
  end

  defp insert_task(slug) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "slug", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [slug])
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
    # The tail's happy path, over a table that already carries rows - the shape a real deploy
    # meets. An empty table would prove less: a concurrent build over one finishes between two
    # statements, so nothing about the build being concurrent would be exercised.
    test "builds a unique index of a populated table in the tail, valid and enforced", %{
      observer: observer,
      scratch: scratch
    } do
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Task, line: 3},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :slug,
            type: :string,
            opts: [optional: true],
            line: 4
          }
        ])

      unique =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: true],
            line: 3
          }
        ])

      first_model = Model.fold(Model.empty(), create.ops)
      full_model = Model.fold(first_model, unique.ops)

      route(scratch, fn ->
        :ok = run([create], first_model, @context)

        insert_task("alpha")
        insert_task("beta")

        :ok = run([create, unique], full_model, @context)
      end)

      assert applied_versions_of(observer) == ["20260813091522", "20260813142237"]

      assert index_flags(observer, "my_app_task_slug_$uidx") == %{unique: true, valid: true}
    end

    test "waits for the migration lock before applying anything", %{
      chain: chain,
      full_model: full_model,
      observer: observer,
      scratch_opts: scratch_opts
    } do
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      # Another node is somewhere inside its own procedure. This one must not start.
      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      applier =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> run(chain, full_model, @context) end)
        end)

      Process.sleep(2 * @poll_interval_ms)

      # Not started, rather than merely not finished: the database is still virgin. Before
      # the one key this assertion would have failed on its first line - the files applied
      # immediately under a key of their own, and only the tail's build waited.
      assert hologram_schema_count(observer) == 0
      assert index_flags(observer) == :absent
      assert Task.yield(applier, 0) == nil

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      assert Task.await(applier, 30_000) == :ok

      # The whole procedure ran once it had the key, tail included: both files recorded, and
      # the index the second file could not build inside its transaction is there and VALID.
      # Valid, not merely present - a concurrent build that fails partway leaves its index in
      # the catalog serving no query while every write maintains it.
      assert applied_versions_of(observer) == ["20260813091522", "20260813142237"]
      assert index_flags(observer) == %{unique: false, valid: true}

      # And it let the key go, so the next node is not stranded behind a finished deploy.
      assert %{rows: [[true]]} =
               Postgrex.query!(observer, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])
    end
  end
end
