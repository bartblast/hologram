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
  alias Hologram.Test.Fixtures.Entity.Module14, as: UserEntity

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

    test "records each file under the hash of the model that file produces" do
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

      add =
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

      mid_model = Model.fold(Model.empty(), create.ops)
      post_model = Model.fold(mid_model, add.ops)

      apply_pending([create, add], Model.empty(), @context)

      statement =
        ~s(SELECT "model_hash" FROM "hologram_system"."migration" ORDER BY "version")

      {:ok, %{rows: rows}} = Connection.query(statement)

      assert rows == [[Model.hash(mid_model)], [Model.hash(post_model)]]
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

    test "fills the rows that predate a required column with its declared default" do
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

      model = apply_pending([create], Model.empty(), @context)

      insert = """
      INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-000000000003', 'existing',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert)

      # Schema reconciliation fills from a declared default in dev, so the applier has to
      # leave the same rows behind for the same declaration, not merely the same column.
      defaulted =
        migration("20260813142237", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :state,
            type: :string,
            opts: [default: "new"],
            line: 3
          }
        ])

      apply_pending([defaulted], model, @context)

      {:ok, %{rows: rows}} =
        Connection.query(~s(SELECT "state" FROM "hologram_data"."my_app_task"))

      assert rows == [["new"]]
    end

    test "keeps another entity type's grants when a shared role name is renamed" do
      # The store tells :editor on one type from :editor on another by resource_type - the
      # enum value is shared - so renaming one type's role must move only its own grants.
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: UserEntity, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{op: :add_role, entity: MyApp.Task, name: :editor, opts: [], line: 5},
          %{op: :create_entity, entity: MyApp.Other, line: 6},
          %{op: :add_role, entity: MyApp.Other, name: :editor, opts: [], line: 7},
          %{op: :designate_user_entity, entity: UserEntity, line: 8}
        ])

      model = apply_pending([create], Model.empty(), @context)

      user_id = "00000000-0000-0000-0000-0000000000a1"

      insert_user = """
      INSERT INTO "hologram_data"."test_fixtures_entity_module14"
        ("id", "created_at", "updated_at")
      VALUES ($1, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert_user, [Ecto.UUID.dump!(user_id)])

      insert_grants = """
      INSERT INTO "hologram_data"."hologram_role_grant"
        ("id", "user_id", "role", "resource_type", "resource_id", "created_at", "updated_at")
      VALUES
        ($1, $3, 'editor', 'my_app_task', $4, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'),
        ($2, $3, 'editor', 'my_app_other', $4, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} =
        Connection.query(insert_grants, [
          Ecto.UUID.dump!("00000000-0000-0000-0000-0000000000b1"),
          Ecto.UUID.dump!("00000000-0000-0000-0000-0000000000b2"),
          Ecto.UUID.dump!(user_id),
          Ecto.UUID.dump!("00000000-0000-0000-0000-0000000000c1")
        ])

      rename =
        migration("20260813142237", [
          %{op: :rename_role, entity: MyApp.Task, from: :editor, to: :reviewer, line: 3}
        ])

      apply_pending([rename], model, @context)

      select = """
      SELECT "resource_type"::text, "role"::text
      FROM "hologram_data"."hologram_role_grant"
      ORDER BY "resource_type"::text
      """

      {:ok, %{rows: rows}} = Connection.query(select)

      assert rows == [["my_app_other", "editor"], ["my_app_task", "reviewer"]]
    end

    test "drops two related entity types whatever their table names sort like" do
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.Author, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.Author,
            opts: [],
            line: 5
          }
        ])

      model = apply_pending([create], Model.empty(), @context)

      # "my_app_author" sorts first, so it is dropped first - which PostgreSQL refuses while
      # my_app_task's foreign key still references it. The names decide the drop order, so
      # they must not decide whether the file applies.
      drop =
        migration("20260813142237", [
          %{op: :delete_entity, entity: MyApp.Author, line: 3},
          %{op: :delete_entity, entity: MyApp.Task, line: 4}
        ])

      apply_pending([drop], model, @context)

      assert table_columns("my_app_author") == []
      assert table_columns("my_app_task") == []
    end

    test "drops the designated user entity type together with its grant store" do
      # "acme_user" sorts before "hologram_role_grant", so the user entity table is dropped
      # while the store's two references to it still stand - the same collision the entity
      # pair above hits, reached through the store nothing declares.
      create =
        migration("20260813091522", [
          %{op: :create_entity, entity: Acme.User, line: 3},
          %{op: :create_entity, entity: MyApp.Other, line: 4},
          %{op: :add_role, entity: MyApp.Other, name: :editor, opts: [], line: 5},
          %{op: :designate_user_entity, entity: Acme.User, line: 6}
        ])

      model = apply_pending([create], Model.empty(), @context)

      user_id = "00000000-0000-0000-0000-0000000000a1"

      insert_user = """
      INSERT INTO "hologram_data"."acme_user" ("id", "created_at", "updated_at")
      VALUES ($1, '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert_user, [Ecto.UUID.dump!(user_id)])

      insert_grant = """
      INSERT INTO "hologram_data"."hologram_role_grant"
        ("id", "user_id", "role", "resource_type", "resource_id", "created_at", "updated_at")
      VALUES ($1, $2, 'editor', 'my_app_other', $3,
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} =
        Connection.query(insert_grant, [
          Ecto.UUID.dump!("00000000-0000-0000-0000-0000000000b1"),
          Ecto.UUID.dump!(user_id),
          Ecto.UUID.dump!("00000000-0000-0000-0000-0000000000c1")
        ])

      drop =
        migration("20260813142237", [
          %{op: :delete_role_grants, line: 3},
          %{op: :delete_entity, entity: Acme.User, line: 4}
        ])

      apply_pending([drop], model, @context)

      assert table_columns("acme_user") == []
      assert table_columns("hologram_role_grant") == []
      assert table_columns("my_app_other") == ["created_at", "id", "updated_at"]
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
            opts: [optional: true],
            line: 4
          }
        ])

      model = apply_pending([create], Model.empty(), @context)

      insert = """
      INSERT INTO "hologram_data"."my_app_task" ("id", "created_at", "updated_at")
      VALUES ('00000000-0000-0000-0000-000000000002',
              '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')
      """

      {:ok, _result} = Connection.query(insert)

      # The existing row holds no title, so requiring one has nothing to give it.
      refused =
        migration("20260813142237", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :title,
            changes: [optional: false],
            line: 3
          }
        ])

      assert_raise RuntimeError, fn -> apply_pending([refused], model, @context) end

      assert applied_versions() == MapSet.new(["20260813091522"])
      assert "title" in table_columns("my_app_task")
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
      #
      # TODO: replace this with a migration once `unique: true` is declarable on an
      # attribute. The only unique index the model derives today is the grant store's,
      # born with its own empty table, so no migration file can produce this op against
      # rows - which is why the op is built by hand here and the check is called rather
      # than the applier. When the option lands, `change_attribute :slug, unique: true`
      # over a populated table exercises the same refusal through the real path, and the
      # applier's whole-file rollback becomes reachable with it (the tail's pre-flight
      # runs after the file's transactional ops have been applied).
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

      record_applied("20260813091522", @context.timestamp, "abc123")
      record_applied("20260813142237", @context.timestamp, "def456")

      assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])
    end

    test "returns an empty set for a freshly claimed database" do
      ensure_managed!(@context)

      assert applied_versions() == MapSet.new()
    end
  end

  describe "check_covered!/2" do
    test "passes a history that produces the model" do
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
        ])
      ]

      model = %{
        entities: %{
          MyApp.Task => %{attributes: [{:title, :string, []}], relationships: [], roles: []}
        },
        roles: %{},
        user_entity: nil
      }

      assert check_covered!(migrations, model) == :ok
    end

    test "raises when model changes have no migration" do
      migrations = [
        migration("20260813091522", [%{op: :create_entity, entity: MyApp.Task, line: 3}])
      ]

      model = %{
        entities: %{
          MyApp.Comment => %{attributes: [], relationships: [], roles: []},
          MyApp.Task => %{attributes: [], relationships: [], roles: []}
        },
        roles: %{MyApp.Roles.Admin => %{extends: []}},
        user_entity: nil
      }

      expected_msg =
        "migration history does not produce this model - " <>
          "2 model changes have no migration (MyApp.Comment, MyApp.Roles.Admin) - " <>
          "run mix holo.gen.migration"

      assert_error RuntimeError, expected_msg, fn -> check_covered!(migrations, model) end
    end

    test "raises naming the designation when it is the only change without a migration" do
      migrations = [
        migration("20260813091522", [%{op: :create_entity, entity: MyApp.Task, line: 3}])
      ]

      # Adding user: true to an entity and not generating the migration leaves every
      # entity and role covered, so the designation is the whole of what is missing.
      model = %{
        entities: %{MyApp.Task => %{attributes: [], relationships: [], roles: []}},
        roles: %{},
        user_entity: MyApp.Task
      }

      expected_msg =
        "migration history does not produce this model - " <>
          "1 model change has no migration (the user entity designation) - " <>
          "run mix holo.gen.migration"

      assert_error RuntimeError, expected_msg, fn -> check_covered!(migrations, model) end
    end

    test "raises naming the designation alongside the entities and roles it accompanies" do
      migrations = [
        migration("20260813091522", [%{op: :create_entity, entity: MyApp.Task, line: 3}])
      ]

      model = %{
        entities: %{
          MyApp.Comment => %{attributes: [], relationships: [], roles: []},
          MyApp.Task => %{attributes: [], relationships: [], roles: []}
        },
        roles: %{},
        user_entity: MyApp.Task
      }

      expected_msg =
        "migration history does not produce this model - " <>
          "2 model changes have no migration (MyApp.Comment, the user entity " <>
          "designation) - run mix holo.gen.migration"

      assert_error RuntimeError, expected_msg, fn -> check_covered!(migrations, model) end
    end
  end

  describe "check_drift!/1" do
    setup do
      ensure_managed!(@context)

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
        ])
      ]

      model = apply_pending(migrations, Model.empty(), @context)

      [mapping: Mapper.derive_from_model!(model)]
    end

    test "passes a database exactly matching the model", %{mapping: mapping} do
      assert check_drift!(mapping) == :ok
    end

    test "passes over the query-derived companions", %{mapping: mapping} do
      add_column =
        ~s{ALTER TABLE "hologram_data"."my_app_task" ADD COLUMN "title_$sort" text}

      {:ok, _result} = Connection.query(add_column)

      assert check_drift!(mapping) == :ok
    end

    test "refuses a hand-added object", %{mapping: mapping} do
      create_index =
        ~s{CREATE INDEX "task_title_hotfix" ON "hologram_data"."my_app_task" ("title")}

      {:ok, _result} = Connection.query(create_index)

      expected_msg =
        normalize_newlines("""
        schema drift detected - the database does not match the model:
          * index "task_title_hotfix" is not derived from the model
        hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
        """)

      assert_error RuntimeError, expected_msg, fn -> check_drift!(mapping) end
    end

    test "refuses a hand-dropped object", %{mapping: mapping} do
      drop_column = ~s(ALTER TABLE "hologram_data"."my_app_task" DROP COLUMN "title")
      {:ok, _result} = Connection.query(drop_column)

      expected_msg =
        normalize_newlines("""
        schema drift detected - the database does not match the model:
          * column "title" on table "my_app_task" declared by the model is missing
        hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
        """)

      assert_error RuntimeError, expected_msg, fn -> check_drift!(mapping) end
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
               system_schema_version: 1,
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

  describe "reconcile_artifacts/1" do
    setup do
      ensure_managed!(@context)

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
        ])
      ]

      model = apply_pending(migrations, Model.empty(), @context)
      sort_key_attributes = MapSet.new([{MyApp.Task, :title}])

      [
        enriched_mapping: Mapper.derive_from_model!(model, sort_key_attributes),
        plain_mapping: Mapper.derive_from_model!(model)
      ]
    end

    test "adds the missing companions and returns the applied ops", %{
      enriched_mapping: enriched_mapping
    } do
      ops = reconcile_artifacts(enriched_mapping)

      assert [%{op: :add_column, table: "my_app_task", column: "title_$sort"}] = ops
      assert "title_$sort" in table_columns("my_app_task")
    end

    test "no-ops on a converged database", %{enriched_mapping: enriched_mapping} do
      reconcile_artifacts(enriched_mapping)

      assert reconcile_artifacts(enriched_mapping) == []
    end

    test "drops the orphaned companions", %{
      enriched_mapping: enriched_mapping,
      plain_mapping: plain_mapping
    } do
      reconcile_artifacts(enriched_mapping)

      ops = reconcile_artifacts(plain_mapping)

      assert [%{op: :drop_column, table: "my_app_task", column: "title_$sort"}] = ops
      refute "title_$sort" in table_columns("my_app_task")
    end

    test "leaves non-artifact drift untouched", %{enriched_mapping: enriched_mapping} do
      drop_column = ~s(ALTER TABLE "hologram_data"."my_app_task" DROP COLUMN "title")
      {:ok, _result} = Connection.query(drop_column)

      ops = reconcile_artifacts(enriched_mapping)

      assert [%{op: :add_column, column: "title_$sort"}] = ops
      refute "title" in table_columns("my_app_task")
    end
  end

  describe "repair_indexes/1" do
    setup do
      ensure_managed!(@context)

      migrations = [
        migration("20260813091522", [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [],
            line: 5
          }
        ])
      ]

      model = apply_pending(migrations, Model.empty(), @context)

      [mapping: Mapper.derive_from_model!(model)]
    end

    test "passes a database carrying every index the model derives", %{mapping: mapping} do
      assert repair_indexes(mapping) == :ok
    end

    test "leaves a table the database does not have to the drift check", %{mapping: mapping} do
      {:ok, _result} = Connection.query(~s{DROP TABLE "hologram_data"."my_app_task"})

      # Its indexes went with it. Creating them here would raise a relation error before
      # check_drift!/1 reports the missing table, which is the cause worth naming.
      assert repair_indexes(mapping) == :ok
    end
  end

  describe "run/3" do
    test "claims the database and applies the pending suffix" do
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

      model = %{
        entities: %{
          MyApp.Task => %{
            attributes: [{:priority, :integer, [optional: true]}, {:title, :string, []}],
            relationships: [],
            roles: []
          }
        },
        roles: %{},
        user_entity: nil
      }

      assert run(migrations, model, @context) == :ok

      assert table_columns("my_app_task") == [
               "created_at",
               "id",
               "priority",
               "title",
               "updated_at"
             ]

      assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])

      # A second run finds nothing pending and changes nothing.
      assert run(migrations, model, @context) == :ok
      assert applied_versions() == MapSet.new(["20260813091522", "20260813142237"])
    end

    test "refuses an uncovered model before touching the database" do
      migrations = []

      model = %{
        entities: %{MyApp.Task => %{attributes: [], relationships: [], roles: []}},
        roles: %{},
        user_entity: nil
      }

      assert_raise RuntimeError, fn -> run(migrations, model, @context) end

      # The check ran before the guard: nothing was claimed.
      statement = """
      SELECT nspname
      FROM pg_catalog.pg_namespace
      WHERE nspname IN ('hologram_data', 'hologram_system')
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      assert rows == []
    end
  end

  describe "record_applied/3" do
    test "records the version with its time and model hash" do
      ensure_managed!(@context)

      assert record_applied("20260813091522", @context.timestamp, "abc123") == :ok

      statement =
        ~s(SELECT "version", "applied_at", "model_hash" FROM "hologram_system"."migration")

      {:ok, %{rows: rows}} = Connection.query(statement)

      assert rows == [["20260813091522", @context.timestamp, "abc123"]]
    end
  end
end
