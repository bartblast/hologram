defmodule Hologram.Test.DatabaseBootstrap do
  @moduledoc false

  # This is not public API yet - it is consumed by the Hologram test suite and by the
  # feature and cluster test apps.
  # TODO: consider promoting to public API (docs, stable surface), so that client apps
  # can bootstrap their own test databases with it.

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.Reflection
  alias Hologram.Test.DatabaseBootstrap.Connection

  @doc """
  Prepares the test databases before a suite runs and returns :ok.

  Each database is created when absent and has its Hologram schemas dropped, so every
  run converges from scratch. The configured test database is always prepared - the
  given names are prepared alongside it, for a suite that exercises more than one
  (a second mechanism, a second app instance).

  A database another app or another env has claimed is refused before anything is
  dropped, and the refusal names the database and whose it is - the claim is the marker
  row the data layer writes in every database it manages, read here on the same
  connection the drop would run on. A database nothing has claimed, or one this app's
  test env has claimed, is dropped whichever mechanism claimed it.

  Runs before anything connects a pool, so it holds no assumption about the app being
  up. Each connection opens synchronously: a server slow to answer is waited for, while
  one that refuses the connection fails at once. A connection that cannot be established
  prints the error with what to check and halts: a usable server is a hard requirement of
  any suite calling this, and every later failure would be noise.

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

    claim = %{otp_app: Atom.to_string(Reflection.otp_app()), env: "test"}

    Enum.each([database_opts[:database] | extra_databases], fn database ->
      ensure_database!(database_opts, database)
      drop_schema_layout!(database_opts, database, claim)
    end)

    :ok
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

  defp create_database_when_absent!(connection_pid, database) do
    # The simple query protocol takes no parameters, so the name goes in as a literal.
    database_existence_query =
      "SELECT 1 FROM pg_database WHERE datname = #{quote_literal(database)}"

    case Connection.query!(connection_pid, database_existence_query) do
      %{rows: []} ->
        quoted_database = Mapper.quote_identifier(database)
        Connection.query!(connection_pid, "CREATE DATABASE #{quoted_database}")

      _result ->
        :ok
    end
  end

  # The connection is stopped on a refusal too, so a caller rescuing the refusal is not left
  # linked to a live connection.
  defp drop_schema_layout!(database_opts, database, claim) do
    {:ok, connection_pid} =
      database_opts
      |> connection_opts(database)
      |> Connection.start()

    try do
      refuse_claimed_elsewhere!(connection_pid, database, claim)
      Enum.each(drop_statements(), &Connection.query!(connection_pid, &1))
    after
      Connection.stop(connection_pid)
    end
  end

  defp drop_statements do
    [
      ~s(DROP SCHEMA IF EXISTS "#{Mapper.system_schema()}" CASCADE),
      ~s(DROP SCHEMA IF EXISTS "#{Mapper.data_schema()}" CASCADE)
    ]
  end

  # The maintenance database always exists, so connecting to it doubles as the server
  # connectivity check.
  defp ensure_database!(database_opts, database) do
    connection_result =
      database_opts
      |> connection_opts("postgres")
      |> Connection.start()

    case connection_result do
      {:ok, connection_pid} ->
        try do
          create_database_when_absent!(connection_pid, database)
        after
          Connection.stop(connection_pid)
        end

      {:error, reason} ->
        print_unusable_server_message(database_opts, reason)
        System.halt(1)
    end
  end

  # Read on this connection: no pool exists yet when this runs, and the marker table may be
  # absent. A table that is absent, or holds no row, is no claim.
  defp marker(connection_pid) do
    system_schema = Mapper.system_schema()
    existence_query = ~s[SELECT to_regclass('"#{system_schema}"."database"')]

    case Connection.query!(connection_pid, existence_query) do
      %{rows: [[nil]]} ->
        nil

      _present ->
        marker_query = ~s(SELECT "otp_app", "env" FROM "#{system_schema}"."database")

        case Connection.query!(connection_pid, marker_query) do
          %{rows: []} -> nil
          %{rows: [[otp_app, env]]} -> %{otp_app: otp_app, env: env}
        end
    end
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

  # Doubles the single quotes. Backslashes stay literal under standard_conforming_strings,
  # which Postgres has on by default since 9.1.
  defp quote_literal(value) do
    "'" <> String.replace(value, "'", "''") <> "'"
  end

  defp refuse_claimed_elsewhere!(connection_pid, database, claim) do
    marker = marker(connection_pid)

    if marker != nil and marker != claim do
      raise ~s(database "#{database}" belongs to the "#{marker.env}" env of app ) <>
              ~s("#{marker.otp_app}" - Hologram.Test.DatabaseBootstrap.run!/1 drops ) <>
              "Hologram's schemas only in a database nothing has claimed or the " <>
              ~s("#{claim.env}" env of app "#{claim.otp_app}" has claimed - point the ) <>
              "test env's config :hologram, :database at another database"
    end
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
