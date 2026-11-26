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
  # The store's two enums are the other half. Their values are the entity type modules and the
  # role names, derived SORTED, and PostgreSQL orders an enum type by a value's POSITION - so a
  # rename whose new label sorts elsewhere has to rebuild the type rather than relabel a value
  # in place, or the database ends up holding the right values in the wrong order. Both renames
  # are tested with a grant that HOLDS the renamed value, since a grant naming nothing (the
  # global shape, both resource columns nil) never exercises the carry.
  #
  # A grant's id is the other thing a rename reaches. It is derived from the grant's labels
  # (RoleGrant.derive_id/4), and the browser and the server's batches find a grant by the id its
  # labels derive - so the grants a rename relabels take new ids, and every grant here is
  # inserted under the id its labels derive, the way the framework writes one.
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

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  @user_id "00000000-0000-0000-0000-0000000000a1"

  # The grant id the given labels derive, its ids written as the store's text reads them - in the
  # 36-character form.
  defp derived_id(user_id, entity_type, entity_id, role) do
    user_id
    |> Entity.uuid_to_id()
    |> RoleGrant.derive_id_from_labels(
      entity_type,
      entity_id && Entity.uuid_to_id(entity_id),
      role
    )
    |> Entity.id_to_uuid()
  end

  # Every grant in the store holds the id its stored labels derive.
  defp assert_ids_derived do
    statement = """
    SELECT "id"::text, "user_id"::text, "entity_type"::text, "entity_id"::text, "role"::text
    FROM "hologram_data"."hologram_role_grant"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    for [id, user_id, entity_type, entity_id, role] <- rows do
      assert id == derived_id(user_id, entity_type, entity_id, role)
    end
  end

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
    SELECT "role"::text, "entity_type"::text
    FROM "hologram_data"."hologram_role_grant"
    ORDER BY "entity_type"::text NULLS FIRST
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [role, entity_type] -> {role, entity_type} end)
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

  # Each grant goes in under the id its labels derive. The labels are the store's spelling: an
  # entity type's module name and a role's, nil for a part the grant leaves out.
  defp insert_grant(entity_type \\ nil, entity_id \\ nil, role \\ "editor") do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "entity_type", "entity_id", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES ($1, $2, $3, $4, $5, now(), now(), 0, now(), 0, now(), '{}')
    """

    id = derived_id(@user_id, entity_type, entity_id, role)

    params = [
      Ecto.UUID.dump!(id),
      Ecto.UUID.dump!(@user_id),
      role,
      entity_type,
      entity_id && Ecto.UUID.dump!(entity_id)
    ]

    {:ok, _result} = Connection.query(statement, params)

    id
  end

  # A second row repeating a grant's four columns, under an id of its own - what an unbuilt
  # unique index over the store lets through.
  defp insert_repeated_grant(entity_type, entity_id, role) do
    statement = """
    INSERT INTO "hologram_data"."hologram_role_grant"
      ("id", "user_id", "role", "entity_type", "entity_id", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now(), 0, now(), 0, now(), '{}')
    """

    params = [Ecto.UUID.dump!(@user_id), role, entity_type, Ecto.UUID.dump!(entity_id)]

    {:ok, _result} = Connection.query(statement, params)
  end

  # Marks the index invalid and stops or restarts writes going through it - a superuser's
  # catalog write, which the test user is.
  defp set_index_ready(index, ready?) do
    {:ok, _result} =
      Connection.query(
        """
        UPDATE pg_catalog.pg_index SET "indisvalid" = false, "indisready" = $1
        WHERE "indexrelid" = '"hologram_data"."#{index}"'::regclass
        """,
        [ready?]
      )
  end

  defp grant_roles do
    statement = """
    SELECT "role"::text FROM "hologram_data"."hologram_role_grant" ORDER BY "role"::text
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [role] -> role end)
  end

  # A grant naming a resource of the designated type - the only grant shape that HOLDS the
  # renamed table name, and so the only one a rename of that type has to carry.
  defp insert_scoped_grant(entity_type), do: insert_grant(entity_type, @user_id)

  defp grant_id(entity_type, entity_id, role) do
    statement = """
    SELECT "id"::text FROM "hologram_data"."hologram_role_grant"
    WHERE "entity_type"::text IS NOT DISTINCT FROM $1
      AND "entity_id" IS NOT DISTINCT FROM $2
      AND "role"::text = $3
    """

    {:ok, %{rows: [[id]]}} =
      Connection.query(statement, [entity_type, entity_id && Ecto.UUID.dump!(entity_id), role])

    id
  end

  defp insert_user(table) do
    statement = """
    INSERT INTO "hologram_data"."#{table}" ("id", "created_at", "server_created_at", "server_created_seq", "server_updated_at", "server_updated_seq", "updated_at", "$revisions")
    VALUES ($1, now(), now(), 0, now(), 0, now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(@user_id)])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
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
      insert_scoped_grant("MyApp.User")
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
        # module - the rows were carried across the rebuild rather than left behind.
        assert grant_rows() == [{"editor", nil}, {"editor", "MyApp.Account"}]

        # "MyApp.Account" sorts before "MyApp.Task", where the old name sorted after it -
        # so the type had to be rebuilt in the model's order, not relabelled in place.
        assert enum_values("hologram_role_grant_entity_type_$enum") == [
                 "MyApp.Account",
                 "MyApp.Task"
               ]

        assert fk_target("hologram_role_grant_user_id_$fk") == "my_app_account"
        assert fk_target("hologram_role_grant_granted_by_id_$fk") == "my_app_account"

        # The grant now naming MyApp.Account holds the id that label derives.
        assert_ids_derived()
      end)
    end

    test "re-derives the ids of the grants an entity rename relabels in place", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # "MyApp.Video" sorts after "MyApp.Task", where "MyApp.User" sat - so the value is
      # relabeled in place rather than through a rebuild.
      renamed =
        migration("20260813142237", [
          %{op: :rename_entity, from: MyApp.User, to: MyApp.Video, line: 3}
        ])

      full_model = Model.fold(first_model, renamed.ops)

      route(scratch, fn ->
        assert run([create, renamed], full_model, @context) == :ok

        assert grant_rows() == [{"editor", nil}, {"editor", "MyApp.Video"}]

        assert enum_values("hologram_role_grant_entity_type_$enum") == [
                 "MyApp.Task",
                 "MyApp.Video"
               ]

        assert_ids_derived()
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
        insert_grant(nil, nil, "viewer")

        assert run([create, renamed], full_model, @context) == :ok

        assert enum_values("hologram_role_grant_role_$enum") == ["admin", "editor"]

        assert grant_roles() == ["admin", "editor", "editor"]
        assert_ids_derived()
      end)
    end

    test "re-derives the ids of only the renamed type's grants when a role name is shared", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # MyApp.User declaring :editor too keeps the value in the enum, so the rename moves only
      # the grants whose entity_type is MyApp.Task.
      renamed =
        migration("20260813142237", [
          %{op: :add_role, entity: MyApp.User, name: :editor, opts: [], line: 3},
          %{op: :rename_role, entity: MyApp.Task, from: :editor, to: :reviewer, line: 4}
        ])

      full_model = Model.fold(first_model, renamed.ops)
      task_id = "00000000-0000-0000-0000-0000000000b1"

      route(scratch, fn ->
        insert_grant("MyApp.Task", task_id, "editor")
        user_grant_id = grant_id("MyApp.User", @user_id, "editor")

        assert run([create, renamed], full_model, @context) == :ok

        assert grant_id("MyApp.Task", task_id, "reviewer") ==
                 derived_id(@user_id, "MyApp.Task", task_id, "reviewer")

        assert grant_id("MyApp.User", @user_id, "editor") == user_grant_id
        assert_ids_derived()
      end)
    end

    test "re-derives the ids of the grants a global role rename relabels", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      added =
        migration("20260813120000", [
          %{op: :add_role, role: MyApp.Roles.Moderator, opts: [], line: 3}
        ])

      renamed =
        migration("20260813142237", [
          %{op: :rename_role, from: MyApp.Roles.Moderator, to: MyApp.Roles.Maintainer, line: 3}
        ])

      added_model = Model.fold(first_model, added.ops)
      full_model = Model.fold(added_model, renamed.ops)

      route(scratch, fn ->
        :ok = run([create, added], added_model, @context)
        insert_grant(nil, nil, "MyApp.Roles.Moderator")

        assert run([create, added, renamed], full_model, @context) == :ok

        assert grant_id(nil, nil, "MyApp.Roles.Maintainer") ==
                 @user_id
                 |> Entity.uuid_to_id()
                 |> RoleGrant.derive_id(nil, nil, MyApp.Roles.Maintainer)
                 |> Entity.id_to_uuid()

        assert_ids_derived()
      end)
    end

    # Each rename re-derives the ids it moved before the next one runs. Re-deriving them once,
    # after the whole file, would move each grant's id onto the one the other still holds.
    test "re-derives the ids of grants whose roles one file swaps", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      swapped =
        migration("20260813142237", [
          %{op: :rename_role, entity: MyApp.Task, from: :editor, to: :swap, line: 3},
          %{op: :rename_role, entity: MyApp.Task, from: :viewer, to: :editor, line: 4},
          %{op: :rename_role, entity: MyApp.Task, from: :swap, to: :viewer, line: 5}
        ])

      full_model = Model.fold(first_model, swapped.ops)
      task_id = "00000000-0000-0000-0000-0000000000b1"

      route(scratch, fn ->
        editor_id = insert_grant("MyApp.Task", task_id, "editor")
        viewer_id = insert_grant("MyApp.Task", task_id, "viewer")

        assert run([create, swapped], full_model, @context) == :ok

        # Each grant took the id its new role derives - the one the other grant held.
        assert grant_id("MyApp.Task", task_id, "editor") == editor_id
        assert grant_id("MyApp.Task", task_id, "viewer") == viewer_id
        assert_ids_derived()
      end)
    end

    # Two rows repeating one grant's columns derive one id, which the primary key refuses to the
    # second. A unique index left unbuilt lets them stand, so the rename is refused naming them.
    test "refuses to re-derive the ids of grants an unbuilt unique index lets repeat", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      # "zebra" sorts after "editor", where "viewer" sat - an in-place relabel, which writes
      # no row, so the re-derivation is the first write to meet the repeat.
      renamed =
        migration("20260813142237", [
          %{op: :rename_role, entity: MyApp.Task, from: :viewer, to: :zebra, line: 3}
        ])

      full_model = Model.fold(first_model, renamed.ops)
      task_id = "00000000-0000-0000-0000-0000000000b1"
      index = "hologram_role_grant_user_id_entity_type_entity_id_role_$uidx"

      route(scratch, fn ->
        # What a build failing on rows that already repeat its key leaves: an invalid index
        # taking no writes. A repeat of a label the rename leaves alone isn't counted.
        insert_grant("MyApp.Task", task_id, "viewer")
        set_index_ready(index, false)
        insert_repeated_grant("MyApp.Task", task_id, "viewer")
        insert_repeated_grant("MyApp.Task", @user_id, "editor")
        insert_repeated_grant("MyApp.Task", @user_id, "editor")

        expected_msg =
          ~s{found 1 duplicate key in "hologram_role_grant" over ("user_id", "entity_type", } <>
            ~s{"entity_id", "role") among the grants a rename moves from "viewer" to "zebra" } <>
            ~s{in "role" - a renamed grant takes the id these columns derive, so the repeats } <>
            "would share one - delete all but one grant of each repeated key"

        assert_error RuntimeError, expected_msg, fn ->
          run([create, renamed], full_model, @context)
        end

        refute renamed.version in applied_versions()
      end)
    end

    test "re-derives the ids of more relabeled grants than one page holds", %{
      create: create,
      first_model: first_model,
      scratch: scratch
    } do
      renamed =
        migration("20260813142237", [
          %{op: :rename_role, entity: MyApp.Task, from: :viewer, to: :admin, line: 3}
        ])

      full_model = Model.fold(first_model, renamed.ops)

      route(scratch, fn ->
        for suffix <- 1..5 do
          insert_grant("MyApp.Task", "00000000-0000-0000-0000-0000000000c#{suffix}", "viewer")
        end

        context = Map.put(@context, :grant_id_page_size, 2)

        assert run([create, renamed], full_model, context) == :ok

        assert grant_roles() == ["admin", "admin", "admin", "admin", "admin", "editor", "editor"]
        assert_ids_derived()
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
        assert grant_rows() == [{"editor", nil}, {"editor", "MyApp.User"}]
        assert fk_target("hologram_role_grant_user_id_$fk") == "my_app_user"
        assert applied_versions() == MapSet.new([create.version])
      end)
    end
  end
end
