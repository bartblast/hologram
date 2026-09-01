defmodule Hologram.Migration.DesignationBeforeRolesTest do
  # An app that designates a user entity before it declares any role. The designation is what
  # puts the role grant store in the model, and the store's `role` column is an enum whose
  # values are the app's role names - so between the designation and the first role the model
  # derives a type with NO values, and the database holds one.
  #
  # That is the state three comparisons have to survive: the deploy that applies the
  # designation, every boot after it, and the deploy that adds the first role. None of them
  # could for as long as introspection listed enum types by their LABELS - a type with no
  # labels contributes no rows, so the comparison read the type as missing while it stood,
  # and answered `create_enum_type` for something the database already had.
  #
  # The scratch tier is what lets the second boot be asked at all: `run/3` needs a database it
  # owns and a history it can commit, and on a database rolled back in between, "the second
  # boot found the type" and "the first boot never created it" are the same observation.
  # `grant_store_test.exs` seeds a role-carrying history for every one of its tests, so a
  # role-LESS history needs a module of its own.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection, so
  # the tier's modules run one at a time to keep the server's connection count bounded.
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

  @designation_ops [
    %{op: :create_entity, entity: MyApp.Task, line: 3},
    %{op: :create_entity, entity: MyApp.User, line: 4},
    %{op: :designate_user_entity, entity: MyApp.User, line: 5}
  ]

  @first_role_ops [
    %{op: :add_role, entity: MyApp.Task, name: :member, opts: [], line: 3}
  ]

  @user_id "00000000-0000-0000-0000-0000000000a1"

  # pg_type, not pg_enum: a type with no values has no labels to find, so asking for
  # its labels answers [] whether or not it exists.
  defp enum_type_exists?(name) do
    statement = """
    SELECT 1
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'hologram_data' AND t.typname = $1 AND t.typtype = 'e'
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [name])

    rows != []
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
      ("id", "user_id", "role", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, 'member', now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(@user_id)])
  end

  defp insert_user(table) do
    statement = """
    INSERT INTO "hologram_data"."#{table}" ("id", "created_at", "updated_at", "$revisions")
    VALUES ($1, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(@user_id)])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  describe "run/3" do
    test "boots a history that designates a user entity before any role", %{scratch: scratch} do
      designation = migration("20260813091522", @designation_ops)
      model = Model.fold(Model.empty(), designation.ops)

      route(scratch, fn ->
        assert run([designation], model, @context) == :ok

        # Both, because a query for LABELS answers [] for a type that does not exist - the
        # existence is the claim, and the emptiness is what makes this history the case.
        assert enum_type_exists?("hologram_role_grant_role_$enum")
        assert enum_values("hologram_role_grant_role_$enum") == []
      end)
    end

    test "boots again on the same history", %{scratch: scratch} do
      designation = migration("20260813091522", @designation_ops)
      model = Model.fold(Model.empty(), designation.ops)

      route(scratch, fn ->
        :ok = run([designation], model, @context)

        assert run([designation], model, @context) == :ok
      end)
    end

    test "adds the first role onto the type and takes a grant of it", %{scratch: scratch} do
      designation = migration("20260813091522", @designation_ops)
      first_role = migration("20260813142237", @first_role_ops)
      first_model = Model.fold(Model.empty(), designation.ops)
      full_model = Model.fold(first_model, first_role.ops)

      route(scratch, fn ->
        :ok = run([designation], first_model, @context)

        assert run([designation, first_role], full_model, @context) == :ok
        assert enum_values("hologram_role_grant_role_$enum") == ["member"]

        # The value arrived by ALTER TYPE onto the standing type rather than by a rebuild,
        # and a grant of it inserting is what proves the type is usable afterwards -
        # insert_grant/0 matches on {:ok, _result}, so a refused insert fails here.
        insert_user("my_app_user")
        insert_grant()
      end)
    end
  end
end
