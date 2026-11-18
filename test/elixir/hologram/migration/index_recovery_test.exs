defmodule Hologram.Migration.IndexRecoveryTest do
  # The two states a deploy can die in that leave an index unfinished, and what the next
  # boot does with each: the index is ABSENT when the node died before its build began, and
  # INVALID when it died partway. Neither heals on its own - the file is recorded as
  # applied, so no later boot revisits it, and an invalid index still reads as present to
  # the drift check.
  #
  # Structurally unreachable from the sandboxed tier, which is why the repair path shipped
  # with only its no-op cases covered: a concurrent build refuses to run inside a
  # transaction and waits on every other transaction that could see the table, and the
  # sandbox is made of both. Everything here is a real build against committed rows.
  #
  # The invalid index is reached the way a crash reaches it, not by writing the catalog:
  # a unique build over rows that duplicate a key fails, and what it leaves behind is what
  # a killed build leaves behind.
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

  # The one unique index the model derives: the grant fact, with nulls compared as values.
  @index "hologram_role_grant_user_id_entity_type_entity_id_role_$uidx"

  @index_op %{
    op: :create_index,
    table: "hologram_role_grant",
    index: @index,
    columns: ["user_id", "entity_type", "entity_id", "role"],
    nulls_distinct: false,
    unique: true
  }

  defp build_index_concurrently do
    concurrent_op = Map.put(@index_op, :concurrently, true)
    [statement] = DDL.statements(concurrent_op)

    Connection.query(statement)
  end

  defp drop_index(index \\ @index) do
    {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{index}"})
  end

  defp grant_count do
    statement = ~s{SELECT COUNT(*) FROM "hologram_data"."hologram_role_grant"}

    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  # :absent, false (a build died partway) or true (the index serves queries).
  defp index_validity(index \\ @index) do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Connection.query(statement, [index]) do
      {:ok, %{rows: [[valid?]]}} -> valid?
      {:ok, %{rows: []}} -> :absent
    end
  end

  # A global grant - both resource columns nil - so two of them collide only because the
  # index compares nulls as values.
  defp insert_global_grant(user_id) do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, 'editor', now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(user_id)])
  end

  defp insert_user(user_id) do
    statement = """
    INSERT INTO "hologram_data"."my_app_user" ("id", "created_at", "updated_at", "$revisions")
    VALUES ($1, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(user_id)])
  end

  defp insert_task(slug) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "slug", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [slug])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  setup %{scratch: scratch} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4},
        %{op: :add_role, entity: MyApp.Task, name: :editor, opts: [], line: 5},
        %{op: :designate_user_entity, entity: MyApp.User, line: 6}
      ])

    model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn ->
      :ok = run([create], model, @context)
    end)

    [chain: [create], mapping: Mapper.derive_from_model!(model), model: model]
  end

  describe "repair_indexes/1" do
    test "builds an index the deploy never got to", %{mapping: mapping, scratch: scratch} do
      route(scratch, fn ->
        # What a node killed before its build began leaves: the file is recorded applied,
        # and the index the model derives is simply not there.
        drop_index()

        assert index_validity() == :absent

        assert repair_indexes(mapping) == :ok

        assert index_validity() == true
      end)
    end

    test "rebuilds an index a failed build left invalid", %{mapping: mapping, scratch: scratch} do
      user_id = "00000000-0000-0000-0000-0000000000a1"

      route(scratch, fn ->
        drop_index()
        insert_user(user_id)

        # Two global grants of the same role to the same user: identical on every indexed
        # column, nils included, which the index refuses only because it compares nulls as
        # values. Written through SQL - the grant API refuses the second one.
        insert_global_grant(user_id)
        insert_global_grant(user_id)

        assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                 build_index_concurrently()

        # The state a node killed mid-build leaves behind, reached by a build that really
        # failed: the index holds the name, serves no query, and every write maintains it.
        assert index_validity() == false

        delete_duplicate = """
        DELETE FROM "hologram_data"."hologram_role_grant"
        WHERE "id" NOT IN (
          SELECT "id" FROM "hologram_data"."hologram_role_grant" LIMIT 1
        )
        """

        {:ok, _result} = Connection.query(delete_duplicate)

        assert grant_count() == 1

        assert repair_indexes(mapping) == :ok

        assert index_validity() == true
      end)
    end
  end

  # A later release meeting the index an interrupted deploy left unfinished: its file renames
  # or drops an index that a build never started, or one that a failed build left invalid.
  describe "run/3" do
    @slug_index "my_app_task_slug_$uidx"

    setup %{chain: chain, model: model, scratch: scratch} do
      # A unique column added to a table that predates the file, so its index builds
      # concurrently, after the file commits.
      add_slug =
        migration("20260813091523", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :slug,
            type: :string,
            opts: [optional: true, unique: true],
            line: 3
          }
        ])

      slug_chain = Enum.concat(chain, [add_slug])
      slug_model = Model.fold(model, add_slug.ops)

      route(scratch, fn ->
        :ok = run(slug_chain, slug_model, @context)
      end)

      [chain: slug_chain, model: slug_model]
    end

    test "builds an index a deploy never got to before a pending file renames it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      rename =
        migration("20260813091524", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}
        ])

      post_model = Model.fold(model, rename.ops)

      route(scratch, fn ->
        # What a node killed after the file committed and before its build began leaves.
        drop_index(@slug_index)

        assert run(Enum.concat(chain, [rename]), post_model, @context) == :ok

        assert index_validity("my_app_task_handle_$uidx") == true
        assert index_validity(@slug_index) == :absent
      end)
    end

    test "builds an index a deploy never got to before a pending file drops it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      drop =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: false],
            line: 3
          }
        ])

      post_model = Model.fold(model, drop.ops)

      route(scratch, fn ->
        drop_index(@slug_index)

        assert run(Enum.concat(chain, [drop]), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # The index can't be rebuilt while rows repeat its key, and it doesn't need to be: it
    # holds its name, so the pending drop finds it and takes it away.
    test "leaves an index a failed build left invalid to the pending file that drops it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      drop =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: false],
            line: 3
          }
        ])

      post_model = Model.fold(model, drop.ops)

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")

        # The repair a boot runs, failing on the repeated key the way a build that died
        # partway fails: the index stays in the catalog, invalid.
        assert_raise MatchError, fn -> repair_indexes(Mapper.derive_from_model!(model)) end

        assert index_validity(@slug_index) == false

        assert run(Enum.concat(chain, [drop]), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end
  end
end
