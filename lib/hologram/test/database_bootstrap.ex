defmodule Hologram.Test.DatabaseBootstrap do
  @moduledoc false

  # This is not public API yet - it is consumed by the Hologram test suite and by the
  # feature and cluster test apps.
  # TODO: consider promoting to public API (docs, stable surface), so that client apps
  # can bootstrap their own test databases with it.

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.Test.DatabaseBootstrap.Connection

  @doc """
  Creates the databases of this test run, points the app at them and returns a map from each
  prepared name, the configured test database's and the given ones, to the name of the run's
  own database.

  Every run gets fresh databases, named after the configured one and the given ones with a
  suffix of the run's own, so two runs against one server, from two checkouts or two in one
  checkout, never touch each other's tables. The configured database itself is never created
  or written to. The :hologram app's :database config is rewritten to name the run's database
  for the configured one, so every connection opened afterwards reaches it - a suite exercising
  more than one database (a second mechanism, a second app instance) reaches the others by the
  names returned.

  Each run database keeps a connection of its own open until the caller ends: linked to it,
  never stopped. Call this from the test helper, whose process lives as long as the run.

  The configured role must be allowed to create databases, since every run creates its own.

  Runs before anything connects a pool, so it holds no assumption about the app being
  up. Each connection opens synchronously: a server slow to answer is waited for, while
  one that refuses the connection fails at once. A connection that cannot be established
  prints the error with what to check and halts: a usable server is a hard requirement of
  any suite calling this, and every later failure would be noise.

  Refuses to run outside the test environment. When neither HOLOGRAM_ENV nor MIX_ENV is set,
  environment detection recognizes the test env by the running ExUnit server, so the call
  belongs after ExUnit.start().
  """
  @spec run!(list(String.t())) :: %{String.t() => String.t()}
  def run!(extra_databases \\ []) do
    refuse_outside_test!()

    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> Config.resolve!(:test)

    run_id =
      4
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    run_databases =
      Map.new([database_opts[:database] | extra_databases], fn database ->
        {database, run_database_name(database, run_id)}
      end)

    maintenance_pid = start_maintenance_connection!(database_opts)

    try do
      Enum.each(run_databases, fn {_database, run_database} ->
        create_database!(maintenance_pid, run_database)
      end)
    after
      Connection.stop(maintenance_pid)
    end

    Enum.each(run_databases, fn {_database, run_database} ->
      hold_database!(database_opts, run_database)
    end)

    # The resolved discrete keys, without :url - a configured url would win over the run's
    # database name.
    Application.put_env(
      :hologram,
      :database,
      Keyword.put(database_opts, :database, run_databases[database_opts[:database]])
    )

    run_databases
  end

  # No handshake timeout: the handshake starts once the server accepted the TCP connection,
  # and a server that is up either finishes it, however long its cold start takes, or closes
  # the socket. The TCP connect itself keeps the driver's timeout.
  defp connection_opts(database_opts, database) do
    [
      database: database,
      handshake_timeout: :infinity,
      hostname: database_opts[:host],
      password: database_opts[:password],
      port: database_opts[:port],
      username: database_opts[:user]
    ]
  end

  # Created from template0, which holds nothing: template1 may have been customised, and a
  # database cannot be copied from a template anyone is connected to.
  defp create_database!(maintenance_pid, database) do
    quoted_database = Mapper.quote_identifier(database)
    Connection.query!(maintenance_pid, "CREATE DATABASE #{quoted_database} TEMPLATE template0")
  end

  defp hold_database!(database_opts, database) do
    {:ok, _connection_pid} =
      database_opts
      |> connection_opts(database)
      |> Connection.start()

    :ok
  end

  defp print_unusable_server_message(database_opts, reason) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(:stderr, """

    Postgres is required to run this test suite, but no connection could be established \
    to #{database_opts[:host]}:#{database_opts[:port]} as user "#{database_opts[:user]}":

      #{Exception.format_banner(:error, reason)}

    The usual causes are:

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
  # Config.resolve!/2 supplies defaults only, so the app's real config wins, and the run's
  # databases would be created on whatever server it names, with the running app's config
  # repointed at them. A release with no HOLOGRAM_ENV reports :dev, so it refuses.
  defp refuse_outside_test! do
    env = Hologram.env()

    if env != :test do
      raise "Hologram.Test.DatabaseBootstrap.run!/1 creates databases and points the " <>
              "database config at them, so it runs in the test env only - the current env " <>
              "is #{inspect(env)}. When neither HOLOGRAM_ENV nor MIX_ENV is set, the test env " <>
              "is recognized by the running ExUnit server, so call run!/1 after ExUnit.start()."
    end
  end

  # Fitted rather than concatenated: PostgreSQL truncates an over-long identifier to 63 bytes
  # without saying so, and a configured name at the limit would lose the run's suffix, so every
  # run would get the same name.
  defp run_database_name(database, run_id) do
    Mapper.fit_identifier([database], [], "run_" <> run_id)
  end

  # The maintenance database always exists, so connecting to it doubles as the server
  # connectivity check.
  defp start_maintenance_connection!(database_opts) do
    connection_result =
      database_opts
      |> connection_opts("postgres")
      |> Connection.start()

    case connection_result do
      {:ok, connection_pid} ->
        connection_pid

      {:error, reason} ->
        print_unusable_server_message(database_opts, reason)
        System.halt(1)
    end
  end
end
