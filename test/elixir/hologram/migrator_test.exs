defmodule Hologram.MigratorTest do
  # async: false - the sandbox isolates data, not locks: DDL on shared relations
  # takes AccessExclusiveLock, which deadlocks with row locks that concurrent
  # sandboxed tests hold until rollback.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.SchemaReconciler

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

  setup do
    drop_hologram_schemas()
    :ok
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
