defmodule Hologram.MigratorTest do
  # async: false - the sandbox isolates data, not locks: DDL on shared relations
  # takes AccessExclusiveLock, which deadlocks with row locks that concurrent
  # sandboxed tests hold until rollback.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  defp claim_as(managed_by) do
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

    SchemaReconciler.create_system_tables()

    SchemaReconciler.write_marker(%{
      otp_app: @context.otp_app,
      env: @context.env,
      managed_by: managed_by,
      hologram_version: @context.hologram_version,
      last_reconciled_at: @context.timestamp
    })
  end

  defp drop_hologram_schemas do
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  defp table_columns(table) do
    statement = """
    SELECT a.attname
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_data' AND c.relname = $1
      AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY a.attname
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [table])

    Enum.map(rows, fn [name] -> name end)
  end

  setup do
    drop_hologram_schemas()
    :ok
  end

  describe "apply_pending/3" do
    # TODO: Two claims of the apply loop cannot be made here, because every test shares
    # one sandboxed connection: that concurrent appliers serialize (advisory locks are
    # per-session, so two processes on one connection share the lock instead of
    # contending for it), and that a killed applier resumes at the file it failed on.
    # The cluster feature tests, whose nodes run as separate systems, cover both.
    setup do
      ensure_managed!(@context)
      :ok
    end

    test "applies a chain, recording each file as it commits" do
      migrations = [
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Task, line: 3},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :title,
            type: :string,
            opts: [],
            line: 4
          }
        ]),
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [optional: true],
            line: 3
          }
        ])
      ]

      post_model = apply_pending(migrations, Model.empty(), @context)

      assert table_columns("my_app_task") == [
               "created_at",
               "id",
               "priority",
               "title",
               "updated_at"
             ]

      assert applied_versions() ==
               MapSet.new(["20260813091522", "20260813142237"])

      assert post_model.entities[MyApp.Task].attributes == [
               {:priority, :integer, [optional: true]},
               {:title, :string, []}
             ]
    end

    test "fills the rows that predate a required column with its backfill" do
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Task, line: 3},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :title,
            type: :string,
            opts: [],
            line: 4
          }
        ])

      apply_pending([create], Model.empty(), @context)

      insert = """
      INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-000000000001', 'existing',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert)

      backfilled =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [backfill: 7],
            line: 3
          }
        ])

      model = apply_pending([create], Model.empty(), @context)
      apply_pending([backfilled], model, @context)

      {:ok, %{rows: rows}} =
        Connection.query(~s(SELECT "priority" FROM "hologram_data"."my_app_task"))

      assert rows == [[7]]
    end

    test "skips the migrations another applier already recorded" do
      migrations = [
        migration("20260813091522", [%{op: :create_entity, entity: MyApp.Task, line: 3}])
      ]

      apply_pending(migrations, Model.empty(), @context)
      schema_after_first = Introspection.schema()

      apply_pending(migrations, Model.empty(), @context)

      assert Introspection.schema() == schema_after_first
      assert applied_versions() == MapSet.new(["20260813091522"])
    end

    test "leaves the earlier files applied when a later one refuses" do
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Task, line: 3},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :title,
            type: :string,
            opts: [],
            line: 4
          }
        ])

      apply_pending([create], Model.empty(), @context)

      insert = """
      INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-000000000002', 'existing',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert)

      # A required column with no backfill has nothing to give the existing row.
      refused =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [],
            line: 3
          }
        ])

      model = apply_pending([create], Model.empty(), @context)

      assert_raise RuntimeError, fn -> apply_pending([refused], model, @context) end

      assert applied_versions() == MapSet.new(["20260813091522"])
      assert "priority" not in table_columns("my_app_task")
    end
  end

  describe "apply_pending/3 tail" do
    setup do
      ensure_managed!(@context)
      :ok
    end

    test "refuses a file whose unique index would meet duplicate rows" do
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

      model = apply_pending([create], Model.empty(), @context)

      insert = """
      INSERT INTO "hologram_data"."my_app_task" ("id", "slug", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-000000000003', 'taken',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'),
             ('00000000-0000-0000-0000-000000000004', 'taken',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert)

      # The unique: attribute option is not declarable yet, so the op the tail would
      # carry is checked directly - the applier runs the same check over its tail.
      unique_index_op = %{
        op: :create_index,
        table: "my_app_task",
        index: "my_app_task_slug_$uidx",
        columns: ["slug"],
        nulls_distinct: true,
        unique: true
      }

      expected_msg =
        ~s{found 1 duplicate key in "my_app_task" over ("slug") - } <>
          "a unique index cannot be built while rows repeat a key - " <>
          "update the rows or drop the unique declaration"

      assert_error RuntimeError, expected_msg, fn ->
        Preflight.run!(
          [unique_index_op],
          Introspection.schema(),
          Mapper.derive_from_model!(model)
        )
      end
    end

    test "leaves a valid index of the same name alone" do
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [optional: true],
            line: 5
          }
        ])

      apply_pending([create], Model.empty(), @context)

      statement = DDL.invalid_index_check_statement("my_app_task_author_id_$idx")
      {:ok, %{rows: [[count]]}} = Connection.query(statement)

      assert count == 0
    end
  end

  describe "applied_versions/0" do
    test "returns the recorded versions" do
      ensure_managed!(@context)

      record_applied("20260813091522", @context.timestamp)
      record_applied("20260813142237", @context.timestamp)

      assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])
    end

    test "returns an empty set for a freshly claimed database" do
      ensure_managed!(@context)

      assert applied_versions() == MapSet.new()
    end
  end

  describe "ensure_managed!/1" do
    test "claims a virgin database for migrations" do
      assert ensure_managed!(@context) == :claimed

      assert SchemaReconciler.read_marker() == %{
               otp_app: "hologram",
               env: "test",
               managed_by: "migrations",
               hologram_version: "0.5.0",
               last_reconciled_at: @context.timestamp
             }

      assert applied_versions() == MapSet.new()
    end

    test "returns :managed when the marker matches the context" do
      ensure_managed!(@context)

      assert ensure_managed!(@context) == :managed
    end

    test "raises for Hologram schemas without a marker" do
      claim_as("migrations")
      {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."database"))

      expected_msg =
        "the configured database contains Hologram schemas but no managed-database " <>
          "marker - it is not managed by migrations - drop the " <>
          ~s("hologram_system" and "hologram_data" schemas or point the config ) <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> ensure_managed!(@context) end
    end

    test "raises for a database belonging to another app" do
      claim_as("migrations")

      expected_msg =
        "the configured database belongs to app \"hologram\" - " <>
          "the current app is \"other_app\" - point the config at the right database"

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(%{@context | otp_app: "other_app"})
      end
    end

    test "raises for a database belonging to another env" do
      claim_as("migrations")

      expected_msg =
        "the configured database belongs to the \"test\" env - " <>
          "the current env is \"prod\" - the config points at another env's database"

      assert_error RuntimeError, expected_msg, fn ->
        ensure_managed!(%{@context | env: "prod"})
      end
    end

    test "raises for a database managed by schema reconciliation" do
      claim_as("reconciliation")

      expected_msg =
        "the configured database is managed by schema reconciliation, which converges " <>
          "dev databases from the model - migrations never apply to one - " <>
          "point the config at a database of this environment"

      assert_error RuntimeError, expected_msg, fn -> ensure_managed!(@context) end
    end
  end

  describe "pending/2" do
    test "returns the migrations the database has not applied, in their order" do
      migrations = [
        %{version: "20260813091522", path: "a.exs", ops: []},
        %{version: "20260813142237", path: "b.exs", ops: []},
        %{version: "20260814080000", path: "c.exs", ops: []}
      ]

      applied = MapSet.new(["20260813091522"])

      assert pending(migrations, applied) == [
               %{version: "20260813142237", path: "b.exs", ops: []},
               %{version: "20260814080000", path: "c.exs", ops: []}
             ]
    end

    test "returns an empty list when every migration is applied" do
      migrations = [%{version: "20260813091522", path: "a.exs", ops: []}]

      assert pending(migrations, MapSet.new(["20260813091522"])) == []
    end
  end

  describe "record_applied/2" do
    test "records the version with its time" do
      ensure_managed!(@context)

      assert record_applied("20260813091522", @context.timestamp) == :ok

      statement = ~s(SELECT "version", "applied_at" FROM "hologram_system"."migration")
      {:ok, %{rows: rows}} = Connection.query(statement)

      assert rows == [["20260813091522", @context.timestamp]]
    end
  end
end
