defmodule Hologram.Migration.GrantStoreTest do
  # What happens to the role grant store when the model underneath it changes. The store is the
  # one table nothing declares - it is derived from the designation - so every move of that
  # designation, and every rename of a name it records, rewrites a table full of rows nobody
  # wrote a migration for.
  #
  # Three changes, three different right answers. Moving the designation elsewhere empties
  # the store, because a grant names a user row and those rows are not the user's any more.
  # Removing the designation takes the store with it. RENAMING the designated type keeps
  # every grant, because nothing moved - the rows are the same rows under a new name, and
  # this is the case people actually hit.
  #
  # The distinction is enforced before any of it runs: the model refuses a file that moves
  # or removes the designation without saying `delete_role_grants()` out loud, and exempts
  # a rename for exactly the reason above. So the destructive cases are always authored,
  # never inferred - and the one that keeps data needs no ceremony.
  #
  # The store's two enums are the other half. Their values are the entity table names and the
  # role names, derived SORTED, and PostgreSQL orders an enum type by a value's POSITION - so a
  # rename whose new label sorts elsewhere has to rebuild the type rather than relabel a value
  # in place, or the database ends up holding the right values in the wrong order. Both renames
  # are tested with a grant that HOLDS the renamed value, since a grant naming nothing (the
  # global shape, both resource columns nil) never exercises the carry.
  #
  # The scratch tier is what lets any of this be asked: the grants have to be COMMITTED
  # before the migration runs, or "the rows survived" and "the rows were never really
  # there" are the same observation.
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

  @user_id "00000000-0000-0000-0000-0000000000a1"

  # The table the grant store's two relationships point at, by constraint name.
  defp fk_target(constraint) do
    statement = """
    SELECT target.relname
    FROM pg_catalog.pg_constraint con
    JOIN pg_catalog.pg_class owner ON owner.oid = con.conrelid
    JOIN pg_catalog.pg_class target ON target.oid = con.confrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = owner.relnamespace
    WHERE n.nspname = 'hologram_data' AND con.contype = 'f' AND con.conname = $1
    """

    case Connection.query(statement, [constraint]) do
      {:ok, %{rows: [[table]]}} -> table
      {:ok, %{rows: []}} -> :absent
    end
  end

  defp grant_rows do
    statement = """
    SELECT "role"::text, "resource_type"::text
    FROM "hologram_data"."hologram_role_grant"
    ORDER BY "resource_type"::text NULLS FIRST
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [role, resource_type] -> {role, resource_type} end)
  end

  defp enum_values(type_name) do
    statement = """
    SELECT e.enumlabel
    FROM pg_catalog.pg_enum e
    JOIN pg_catalog.pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = $1
    ORDER BY e.enumsortorder
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [type_name])

    Enum.map(rows, fn [value] -> value end)
  end

  defp insert_grant do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, 'editor', now(), now())
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(@user_id)])
  end

  # A grant naming a resource of the designated type - the only grant shape that HOLDS the
  # renamed table name, and so the only one a rename of that type has to carry.
  defp grant_roles do
    statement = """
    SELECT "role"::text FROM "hologram_data"."hologram_role_grant" ORDER BY "role"::text
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [role] -> role end)
  end

  defp insert_role_grant(role) do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, $2, now(), now())
    """

    {:ok, _result} =
      Connection.query(statement, [Ecto.UUID.dump!(@user_id), Atom.to_string(role)])
  end

  defp insert_scoped_grant(resource_type) do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "resource_type", "resource_id", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, 'editor', $2, $1, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(@user_id), resource_type])
  end

  defp insert_user(table) do
    statement = """
    INSERT INTO "hologram_data"."#{table}" ("id", "created_at", "updated_at")
    VALUES ($1, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(@user_id)])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  defp store_exists? do
    statement = ~s{SELECT to_regclass('hologram_data.hologram_role_grant')}

    {:ok, %{rows: [[regclass]]}} = Connection.query(statement)

    regclass != nil
  end

  setup %{scratch: scratch} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4},
        %{op: :add_role, entity: MyApp.Task, name: :editor, opts: [], line: 5},
        %{op: :add_role, entity: MyApp.Task, name: :viewer, opts: [], line: 6},
        %{op: :designate_user_entity, entity: MyApp.User, line: 7}
      ])

    first_model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn ->
      :ok = run([create], first_model, @context)

      insert_user("my_app_user")
      insert_grant()
      insert_scoped_grant("my_app_user")
    end)

    [create: create, first_model: first_model]
  end

  describe "run/3" do
    test "keeps every grant when the designated type is renamed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # No delete_role_grants, and none is demanded: the designation follows the rename,
      # so the grants still name the very rows they always named.
      renamed =
        migration("20260813142237", [
          %{op: :rename_entity, from: MyApp.User, to: MyApp.Account, line: 3}
        ])

      full_model = Model.fold(first_model, renamed.ops)

      route(scratch, fn ->
        assert run([create, renamed], full_model, @context) == :ok

        # Both grants stand, and the one naming the renamed type now names it by its new
        # table - the rows were carried across the rebuild rather than left behind.
        assert grant_rows() == [{"editor", nil}, {"editor", "my_app_account"}]

        # "my_app_account" sorts before "my_app_task", where the old name sorted after it -
        # so the type had to be rebuilt in the model's order, not relabelled in place.
        assert enum_values("hologram_role_grant_resource_type_$enum") == [
                 "my_app_account",
                 "my_app_task"
               ]

        assert fk_target("hologram_role_grant_user_id_$fk") == "my_app_account"
        assert fk_target("hologram_role_grant_granted_by_id_$fk") == "my_app_account"
      end)
    end

    test "keeps every grant when a role is renamed past its neighbours", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # :admin sorts before :editor, where :viewer sorted after it - the same position move
      # the entity rename above makes, reached through the store's other enum.
      renamed =
        migration("20260813142237", [
          %{op: :rename_role, entity: MyApp.Task, from: :viewer, to: :admin, line: 3}
        ])

      full_model = Model.fold(first_model, renamed.ops)

      route(scratch, fn ->
        insert_role_grant(:viewer)

        assert run([create, renamed], full_model, @context) == :ok

        assert enum_values("hologram_role_grant_role_$enum") == ["admin", "editor"]

        assert grant_roles() == ["admin", "editor", "editor"]
      end)
    end

    test "empties the store and re-points it when the designation moves", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      moved =
        migration("20260813142237", [
          %{op: :delete_role_grants, line: 3},
          %{op: :create_entity, entity: MyApp.Account, line: 4},
          %{op: :designate_user_entity, entity: MyApp.Account, line: 5}
        ])

      full_model = Model.fold(first_model, moved.ops)

      route(scratch, fn ->
        assert run([create, moved], full_model, @context) == :ok

        # The grants named rows of a type that is not the user any more, so the file said
        # so and they are gone - while the store itself stands, now pointing elsewhere.
        assert grant_rows() == []
        assert fk_target("hologram_role_grant_user_id_$fk") == "my_app_account"
        assert fk_target("hologram_role_grant_granted_by_id_$fk") == "my_app_account"
      end)
    end

    test "drops the store when the designation is removed", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      removed =
        migration("20260813142237", [
          %{op: :delete_role_grants, line: 3},
          %{op: :designate_user_entity, entity: nil, line: 4}
        ])

      full_model = Model.fold(first_model, removed.ops)

      route(scratch, fn ->
        assert run([create, removed], full_model, @context) == :ok

        # Nothing derives the store any more, so it goes entirely - not merely emptied.
        refute store_exists?()
        assert fk_target("hologram_role_grant_user_id_$fk") == :absent
      end)
    end

    test "refuses to move the designation while grants still reference it", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # The same move as above, without saying delete_role_grants() - the destruction is
      # never inferred, because a reviewer reading the file would not see it.
      unsaid =
        migration("20260813142237", [
          %{op: :create_entity, entity: MyApp.Account, line: 3},
          %{op: :designate_user_entity, entity: MyApp.Account, line: 4}
        ])

      expected_msg =
        "the user entity designation moves from MyApp.User to MyApp.Account, and role " <>
          "grants reference MyApp.User rows - add `delete_role_grants()` above it, which " <>
          "empties the role grant store in the same migration"

      route(scratch, fn ->
        assert_error Hologram.CompileError, expected_msg, fn ->
          Model.fold(first_model, unsaid.ops)
        end

        # Nothing ran: the file never became a model, so it never reached the database.
        assert grant_rows() == [{"editor", nil}, {"editor", "my_app_user"}]
        assert fk_target("hologram_role_grant_user_id_$fk") == "my_app_user"
        assert applied_versions() == MapSet.new([create.version])
      end)
    end
  end
end
