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

  # The one index the model derives beyond the keys and foreign keys, and the only unique
  # one: the grant fact, with nulls compared as values.
  @index "hologram_role_grant_$uidx"

  @index_op %{
    op: :create_index,
    table: "hologram_role_grant",
    index: @index,
    columns: ["user_id", "resource_type", "resource_id", "role"],
    nulls_distinct: false,
    unique: true
  }

  defp build_index_concurrently do
    concurrent_op = Map.put(@index_op, :concurrently, true)
    [statement] = DDL.statements(concurrent_op)

    Connection.query(statement)
  end

  defp drop_index do
    {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{@index}"})
  end

  defp grant_count do
    statement = ~s{SELECT COUNT(*) FROM "hologram_data"."hologram_role_grant"}

    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  # :absent, false (a build died partway) or true (the index serves queries).
  defp index_validity do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Connection.query(statement, [@index]) do
      {:ok, %{rows: [[valid?]]}} -> valid?
      {:ok, %{rows: []}} -> :absent
    end
  end

  # A global grant - both resource columns nil - so two of them collide only because the
  # index compares nulls as values.
  defp insert_global_grant(user_id) do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, 'editor', now(), now())
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(user_id)])
  end

  defp insert_user(user_id) do
    statement = """
    INSERT INTO "hologram_data"."my_app_user" ("id", "created_at", "updated_at")
    VALUES ($1, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(user_id)])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
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

    [mapping: Mapper.derive_from_model!(model), model: model]
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
end
