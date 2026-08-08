defmodule HologramFeatureTests.DatabaseBootstrap do
  @moduledoc false

  # Boots the feature test database before the suite runs: creates the database when
  # absent and drops the Hologram schemas, so every run converges from scratch - the
  # feature app declares entities, which activates the Hologram database at app boot,
  # and the boot-time reconciliation recreates the schema layout.

  alias Hologram.Database.Config, as: DatabaseConfig

  @drop_statements [
    ~s(DROP SCHEMA IF EXISTS "hologram_system" CASCADE),
    ~s(DROP SCHEMA IF EXISTS "hologram_data" CASCADE)
  ]

  @spec run!() :: :ok
  def run! do
    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> DatabaseConfig.resolve!(:test)

    ensure_database!(database_opts)
    drop_schema_layout!(database_opts)

    :ok
  end

  defp connection_opts(database_opts, database) do
    [
      database: database,
      hostname: database_opts[:host],
      password: database_opts[:password],
      port: database_opts[:port],
      username: database_opts[:user]
    ]
  end

  defp drop_schema_layout!(database_opts) do
    {:ok, conn} =
      database_opts
      |> connection_opts(database_opts[:database])
      |> Postgrex.start_link()

    Enum.each(@drop_statements, &Postgrex.query!(conn, &1, []))

    GenServer.stop(conn)
  end

  defp ensure_database!(database_opts) do
    {:ok, conn} =
      database_opts
      |> connection_opts("postgres")
      |> Postgrex.start_link()

    database = database_opts[:database]

    %{rows: rows} =
      Postgrex.query!(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [database])

    if rows == [] do
      Postgrex.query!(conn, ~s(CREATE DATABASE "#{database}"), [])
    end

    GenServer.stop(conn)
  end
end
