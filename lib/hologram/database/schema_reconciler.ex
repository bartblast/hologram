defmodule Hologram.Database.SchemaReconciler do
  @moduledoc false

  alias Hologram.Database.Connection

  # Control-plane bookkeeping DDL - static and framework-owned, never model-derived.
  # The database table is the managed-database marker (single row, maintained by
  # write_marker/1) - the schema_object table is the managed-object registry.
  @system_statements [
    """
    CREATE TABLE "hologram_system"."database" (
      "otp_app" text NOT NULL,
      "env" text NOT NULL,
      "managed_by" text NOT NULL,
      "hologram_version" text NOT NULL,
      "last_reconciled_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_system"."schema_object" (
      "kind" text NOT NULL,
      "parent" text NOT NULL,
      "name" text NOT NULL,
      PRIMARY KEY ("kind", "parent", "name")
    )
    """
  ]

  @doc """
  Creates the control-plane bookkeeping tables in the hologram_system schema.
  """
  @spec create_system_tables() :: :ok
  def create_system_tables do
    Enum.each(@system_statements, fn statement ->
      {:ok, _result} = Connection.query(statement)
    end)

    :ok
  end

  @doc """
  Returns the managed-database marker, or nil when none has been written.

  The marker is a map with :otp_app, :env, and :managed_by (the guard facts, as
  strings) plus :hologram_version and :last_reconciled_at (diagnostics).
  """
  @spec read_marker() :: %{atom => any} | nil
  def read_marker do
    statement = """
    SELECT "otp_app", "env", "managed_by", "hologram_version", "last_reconciled_at"
    FROM "hologram_system"."database"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    case rows do
      [] ->
        nil

      [[otp_app, env, managed_by, hologram_version, last_reconciled_at]] ->
        %{
          otp_app: otp_app,
          env: env,
          managed_by: managed_by,
          hologram_version: hologram_version,
          last_reconciled_at: last_reconciled_at
        }
    end
  end

  @doc """
  Writes the given marker as the single row of the managed-database marker table,
  replacing any previous row.
  """
  @spec write_marker(%{atom => any}) :: :ok
  def write_marker(marker) do
    {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."database"))

    insert_statement = """
    INSERT INTO "hologram_system"."database"
      ("otp_app", "env", "managed_by", "hologram_version", "last_reconciled_at")
    VALUES ($1, $2, $3, $4, $5)
    """

    params = [
      marker.otp_app,
      marker.env,
      marker.managed_by,
      marker.hologram_version,
      marker.last_reconciled_at
    ]

    {:ok, _result} = Connection.query(insert_statement, params)

    :ok
  end
end
