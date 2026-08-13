defmodule Hologram.Test.DatabaseBootstrap do
  @moduledoc false

  # This is not public API yet - it is consumed by the Hologram test suite and by the
  # feature, umbrella and cluster tests apps.
  # TODO: consider promoting to public API (docs, stable surface), so that client apps
  # can bootstrap their own test databases with it.

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper

  @drop_statements [
    ~s(DROP SCHEMA IF EXISTS "hologram_system" CASCADE),
    ~s(DROP SCHEMA IF EXISTS "hologram_data" CASCADE)
  ]

  @doc """
  Prepares the test databases before a suite runs and returns :ok.

  Each database is created when absent and has its Hologram schemas dropped, so every
  run converges from scratch. The configured test database is always prepared - the
  given names are prepared alongside it, for a suite that exercises more than one
  (a second mechanism, a second app instance).

  Runs before anything connects a pool, so it holds no assumption about the app being
  up. An unreachable Postgres server prints how to start one and halts: the server is a
  hard requirement of any suite calling this, and every later failure would be noise.
  """
  @spec run!(list(String.t())) :: :ok
  def run!(extra_databases \\ []) do
    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> Config.resolve!(:test)

    Enum.each([database_opts[:database] | extra_databases], fn database ->
      ensure_database!(database_opts, database)
      drop_schema_layout!(database_opts, database)
    end)

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

  defp drop_schema_layout!(database_opts, database) do
    {:ok, connection_pid} =
      database_opts
      |> connection_opts(database)
      |> Postgrex.start_link()

    Enum.each(@drop_statements, &Postgrex.query!(connection_pid, &1, []))

    GenServer.stop(connection_pid)
  end

  defp ensure_database!(database_opts, database) do
    {:ok, connection_pid} =
      database_opts
      |> connection_opts("postgres")
      |> Postgrex.start_link()

    database_existence_query = "SELECT 1 FROM pg_database WHERE datname = $1"

    # The maintenance database always exists, so this query doubles as the server
    # connectivity check.
    case Postgrex.query(connection_pid, database_existence_query, [database]) do
      {:ok, %{rows: []}} ->
        quoted_database = Mapper.quote_identifier(database)
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

    Postgres is required to run this test suite, but no server is reachable at \
    #{database_opts[:host]}:#{database_opts[:port]} (user "#{database_opts[:user]}").

    Start a local Postgres server, e.g.:
      * macOS (Homebrew): brew services start postgresql
      * Linux (systemd): sudo systemctl start postgresql
      * Docker: docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres

    Override the connection settings with config :hologram, :database in config/test.exs.
    """)
  end
end
