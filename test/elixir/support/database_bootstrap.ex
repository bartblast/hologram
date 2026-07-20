defmodule Hologram.Test.DatabaseBootstrap do
  @moduledoc false

  # Boots the test database before the suite runs: verifies that the Postgres server is
  # reachable (Postgres is a hard requirement of the test suite - unreachable server means
  # fail fast with instructions), creates the test database when absent, and drops the
  # Hologram schemas so the suite starts virgin. The fixture schema layout is then created
  # by schema reconciliation once the pool is up - test_helper.exs calls the reconciler
  # directly, making the suite auto-sync's own first consumer.

  alias Hologram.Database.Config, as: DatabaseConfig
  alias Hologram.Database.Mapper

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
    {:ok, connection_pid} =
      database_opts
      |> connection_opts(database_opts[:database])
      |> Postgrex.start_link()

    Enum.each(@drop_statements, &Postgrex.query!(connection_pid, &1, []))

    GenServer.stop(connection_pid)
  end

  defp ensure_database!(database_opts) do
    {:ok, connection_pid} =
      database_opts
      |> connection_opts("postgres")
      |> Postgrex.start_link()

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
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
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
end
