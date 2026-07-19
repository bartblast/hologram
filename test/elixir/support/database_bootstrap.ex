defmodule Hologram.Test.DatabaseBootstrap do
  @moduledoc false

  # Boots the test database before the suite runs: verifies that the Postgres server is
  # reachable (Postgres is a hard requirement of the test suite - unreachable server means
  # fail fast with instructions), creates the test database when absent, and recreates the
  # schema layout for the entity fixture modules from scratch.
  # TODO: replace the hand-authored DDL with schema auto-sync once the migration engine exists.

  alias Hologram.Database.Config, as: DatabaseConfig
  alias Hologram.Database.Mapper

  # Statement order follows dependencies: schemas first, then the enum type, then tables
  # before the tables that reference them, join table and its reverse index last.
  @schema_statements [
    ~s(DROP SCHEMA IF EXISTS "hologram_system" CASCADE),
    ~s(CREATE SCHEMA "hologram_system"),
    ~s(DROP SCHEMA IF EXISTS "hologram_data" CASCADE),
    ~s(CREATE SCHEMA "hologram_data"),
    ~s[CREATE TYPE "hologram_data"."test_fixtures_entity_module4_c_$enum" AS ENUM ('x', 'y')],
    """
    CREATE TABLE "hologram_data"."test_fixtures_entity_module1" (
      "id" uuid PRIMARY KEY,
      "created_at" timestamptz NOT NULL,
      "updated_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_data"."test_fixtures_entity_module2" (
      "id" uuid PRIMARY KEY,
      "a" boolean NOT NULL,
      "b" int8,
      "c" text COLLATE "C" NOT NULL,
      "created_at" timestamptz NOT NULL,
      "updated_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_data"."test_fixtures_entity_module3" (
      "id" uuid PRIMARY KEY,
      "b_id" uuid REFERENCES "hologram_data"."test_fixtures_entity_module2" ("id") ON DELETE RESTRICT,
      "c_id" uuid NOT NULL REFERENCES "hologram_data"."test_fixtures_entity_module1" ("id") ON DELETE RESTRICT,
      "created_at" timestamptz NOT NULL,
      "updated_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_data"."test_fixtures_entity_module4" (
      "id" uuid PRIMARY KEY,
      "a" date NOT NULL,
      "b" timestamptz NOT NULL,
      "c" "hologram_data"."test_fixtures_entity_module4_c_$enum" NOT NULL,
      "d" float8 NOT NULL,
      "created_at" timestamptz NOT NULL,
      "updated_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_data"."test_fixtures_entity_module3_a_$join" (
      "source_id" uuid NOT NULL REFERENCES "hologram_data"."test_fixtures_entity_module3" ("id") ON DELETE RESTRICT,
      "target_id" uuid NOT NULL REFERENCES "hologram_data"."test_fixtures_entity_module2" ("id") ON DELETE RESTRICT,
      PRIMARY KEY ("source_id", "target_id")
    )
    """,
    ~s[CREATE INDEX "test_fixtures_entity_module3_a_$join_target_id_$idx" ON "hologram_data"."test_fixtures_entity_module3_a_$join" ("target_id", "source_id")]
  ]

  @spec run!() :: :ok
  def run! do
    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> DatabaseConfig.resolve!(:test)

    ensure_database!(database_opts)
    recreate_schema_layout!(database_opts)

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

  defp ensure_database!(database_opts) do
    {:ok, connection_pid} = Postgrex.start_link(connection_opts(database_opts, "postgres"))

    database_existence_query = "SELECT 1 FROM pg_database WHERE datname = $1"

    # The maintenance database always exists, so this query doubles as the server
    # connectivity check.
    case Postgrex.query(connection_pid, database_existence_query, [database_opts[:database]]) do
      {:ok, %{rows: []}} ->
        quoted_database = Mapper.quote_identifier(database_opts[:database])
        Postgrex.query!(connection_pid, "CREATE DATABASE #{quoted_database}", [])

      {:ok, _result} ->
        :ok

      {:error, _reason} ->
        print_unreachable_server_message(database_opts)
        System.halt(1)
    end

    GenServer.stop(connection_pid)
  end

  defp print_unreachable_server_message(database_opts) do
    IO.puts(:stderr, """

    Postgres is required to run the Hologram test suite, but no server is reachable at \
    #{database_opts[:host]}:#{database_opts[:port]} (user "#{database_opts[:user]}").

    Start a local Postgres server, e.g.:
      * macOS (Homebrew): brew services start postgresql
      * Linux (systemd): sudo systemctl start postgresql
      * Docker: docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres

    Override the connection settings with config :hologram, :database in config/test.exs.
    """)
  end

  defp recreate_schema_layout!(database_opts) do
    {:ok, connection_pid} =
      Postgrex.start_link(connection_opts(database_opts, database_opts[:database]))

    Enum.each(@schema_statements, &Postgrex.query!(connection_pid, &1, []))

    GenServer.stop(connection_pid)
  end
end
