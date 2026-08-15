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
  up. A connection that cannot be established prints what to check and halts: a usable
  server is a hard requirement of any suite calling this, and every later failure would
  be noise.

  Refuses to run outside the test environment - the schema drop is what makes this
  function test-only. When neither HOLOGRAM_ENV nor MIX_ENV is set, environment
  detection recognizes the test env by the running ExUnit server, so the call belongs
  after ExUnit.start().
  """
  @spec run!(list(String.t())) :: :ok
  def run!(extra_databases \\ []) do
    refuse_outside_test!()

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

      # The reason carried here is always the pool's :queue_timeout, whatever went wrong -
      # the driver retries in the background and this is the wait giving up. What actually
      # failed is in the connection error the driver logged just above, so the message
      # names the candidates and sends the reader there rather than asserting one.
      {:error, _reason} ->
        print_unusable_server_message(database_opts)
        System.halt(1)
    end

    GenServer.stop(connection_pid)
  end

  defp print_unusable_server_message(database_opts) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(:stderr, """

    Postgres is required to run this test suite, but no connection could be established \
    to #{database_opts[:host]}:#{database_opts[:port]} as user \
    "#{database_opts[:user]}". The connection error logged above says which of these it is:

      * no server is running there - start one, e.g.
          macOS (Homebrew): brew services start postgresql
          Linux (systemd): sudo systemctl start postgresql
          Docker: docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres
      * the credentials are refused - check the user and password
      * the "postgres" maintenance database is missing - this bootstrap connects to it \
    to create the test databases

    Override the connection settings with config :hologram, :database in config/test.exs.
    """)
  end

  # The prod path this closes is one line in a release console: the :test atom passed to
  # Config.resolve!/2 supplies defaults only, so the app's real config wins and the drop
  # statements would land in whatever database it names. A release with no HOLOGRAM_ENV
  # reports :dev, so it refuses.
  defp refuse_outside_test! do
    env = Hologram.env()

    if env != :test do
      raise "Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's schemas and runs " <>
              "in the test env only - the current env is #{inspect(env)}. When neither " <>
              "HOLOGRAM_ENV nor MIX_ENV is set, the test env is recognized by the " <>
              "running ExUnit server, so call run!/1 after ExUnit.start()."
    end
  end
end
