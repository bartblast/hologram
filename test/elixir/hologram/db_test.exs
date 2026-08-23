defmodule Hologram.DBTest do
  # async: false - the boot-mechanism tests flip the HOLOGRAM_ENV env var, which is global.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module19

  describe "init/1" do
    test "starts only the connection pool in test" do
      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool]
    end

    test "adds the schema reconciliation boot step in dev" do
      System.put_env("HOLOGRAM_ENV", "dev")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :schema_reconciliation]
    end

    test "adds the migration apply boot step outside dev and test" do
      System.put_env("HOLOGRAM_ENV", "prod")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      # Only dev and test carry default connection options - a prod resolve needs them
      # configured, though nothing connects here (init/1 only builds the child specs).
      database_config = Application.get_env(:hologram, :database, [])

      Application.put_env(:hologram, :database,
        database: "my_app_prod",
        host: "db.internal",
        password: "secret",
        user: "my_app"
      )

      on_exit(fn -> Application.put_env(:hologram, :database, database_config) end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :migrations]
    end
  end

  describe "mapping/0" do
    test "returns the mapping derived from the discovered entity types" do
      assert mapping() == Mapper.derive!(Reflection.list_entities())
    end
  end

  describe "pool_name/0" do
    test "names a running connection pool that executes queries" do
      assert Postgrex.query!(pool_name(), "SELECT 1", []).rows == [[1]]
    end
  end

  describe "reconciliation_context/0" do
    test "carries the mapping, guard facts, and marker diagnostics" do
      context = reconciliation_context()

      assert context.mapping == mapping()
      assert context.otp_app == "hologram"
      assert context.env == "test"
      assert context.hologram_version == Mix.Project.config()[:version]
      assert %DateTime{} = context.timestamp
    end
  end

  describe "create/1" do
    # Both shapes in one test: the first create binds {:ok, _} or the match fails, and the
    # second pins the violation travelling out through the gateway unchanged.
    test "returns the unique violation" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "x")
        |> create()

      result =
        Module19
        |> Entity.new(slug: "x")
        |> create()

      assert result == {:error, %{slug: [:unique]}}
    end

    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn -> create(%RoleGrant{}) end
    end
  end

  describe "create!/1" do
    test "returns the created entity" do
      entity =
        Module1
        |> Entity.new()
        |> create!()

      assert entity.created_at
      assert get(Module1, entity.id).id == entity.id
    end

    # assert_error sees the message and nothing else, so the reason field - what the plain
    # variant would have returned - is caught and asserted separately.
    test "raises a write conflict when a unique attribute's value is taken" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "x")
        |> create()

      expected_msg =
        ~s(cannot create Hologram.Test.Fixtures.Entity.Module19 - slug "x" is already taken)

      assert_error Hologram.WriteConflictError, expected_msg, fn ->
        Module19
        |> Entity.new(slug: "x")
        |> create!()
      end

      error =
        try do
          Module19
          |> Entity.new(slug: "x")
          |> create!()
        rescue
          error in Hologram.WriteConflictError -> error
        end

      assert error.reason == %{slug: [:unique]}
    end
  end

  describe "delete/2" do
    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn ->
        delete(RoleGrant, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end
  end

  describe "reload/0" do
    test "re-derives the mapping and reconciles the schema" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload() == :ok

      assert Introspection.schema() == Schema.from_mapping(mapping())
    end
  end

  describe "update/3" do
    test "returns the unique violation" do
      {:ok, first} =
        Module19
        |> Entity.new(slug: "held")
        |> create()

      {:ok, second} =
        Module19
        |> Entity.new(slug: "other")
        |> create()

      assert update(Module19, second.id, slug: first.slug) == {:error, %{slug: [:unique]}}
    end

    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn ->
        update(RoleGrant, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f", role: :owner)
      end
    end
  end

  describe "update/1" do
    test "raises a teaching error for a struct argument" do
      entity = Entity.new(Module1)

      expected_msg =
        "update takes explicit changes, not a modified struct - pass the changed attributes: " <>
          "DB.update(Hologram.Test.Fixtures.Entity.Module1, entity.id, attribute: value). " <>
          "Full-row writes from a struct aren't supported: they would overwrite concurrent " <>
          "changes to fields you didn't touch."

      assert_error ArgumentError, expected_msg, fn -> update(entity) end
    end
  end
end
