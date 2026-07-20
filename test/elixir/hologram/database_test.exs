defmodule Hologram.DatabaseTest do
  # async: false - the dev-boot test flips the HOLOGRAM_ENV env var, which is global.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Database

  alias Hologram.Database.Connection
  alias Hologram.Database.Introspection
  alias Hologram.Database.Mapper
  alias Hologram.Database.Schema
  alias Hologram.Reflection

  describe "init/1" do
    test "starts only the connection pool outside dev" do
      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool]
    end

    test "adds the schema reconciliation boot step in dev" do
      System.put_env("HOLOGRAM_ENV", "dev")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :schema_reconciliation]
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

  describe "reload/0" do
    test "re-derives the mapping and reconciles the schema" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload() == :ok

      assert Introspection.schema() == Schema.from_mapping(mapping())
    end
  end
end
