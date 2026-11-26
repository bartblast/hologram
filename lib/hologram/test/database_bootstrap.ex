defmodule Hologram.Test.DatabaseBootstrap do
  @moduledoc false

  # Not public API: apps reach it through Hologram.Test.setup/0, while Hologram's own suite and
  # test apps call it directly.

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Migration.ShadowVerifier
  alias Hologram.Test.DatabaseBootstrap.Connection

  # What a later run's sweep tells a test database by - never its name, so a database whose name
  # only looks like one is never dropped. No quotes, so it goes into SQL as a literal unescaped.
  @mark "Hologram test database, dropped by a later test run once nothing is connected"

  @ran_key {__MODULE__, :ran}

  @doc """
  Creates the given database through the given connection, empty.
  """
  @spec create_database!(pid, String.t()) :: Postgrex.Result.t()
  # From template0, which holds nothing: template1 may have been customised, and a database
  # cannot be copied from a template anyone is connected to.
  def create_database!(maintenance_pid, database) do
    quoted_database = Mapper.quote_identifier(database)
    Connection.query!(maintenance_pid, "CREATE DATABASE #{quoted_database} TEMPLATE template0")
  end

  @doc """
  Returns the comment a test database carries for a later run to drop it once nothing is
  connected to it.

  For a test support module creating databases of its own, which marks each one once a
  connection to it is up, with `COMMENT ON DATABASE`. Marked before that, a database could be
  dropped by a run starting meanwhile.
  """
  @spec mark() :: String.t()
  def mark, do: @mark

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

  The databases runs left behind are dropped here: every database carrying the mark (see
  mark/0) that the configured role owns and nothing is connected to, together with the
  scratch database the shadow verifier named after it. A run's database gets the mark only
  once its held connection is up, so one with the mark and no session belongs to a run that
  ended, crashed or was killed, whose sessions the server ended with its sockets.

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
    refuse_outside_test!(
      "Hologram.Test.DatabaseBootstrap.run!/1 creates and drops databases and points the " <>
        "database config at them",
      "run!/1"
    )

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
      maintenance_pid
      |> list_leftover_databases()
      |> Enum.each(&drop_leftover_database!(maintenance_pid, &1))

      Enum.each(run_databases, fn {_database, run_database} ->
        create_database!(maintenance_pid, run_database)
        hold_database!(maintenance_pid, database_opts, run_database)
      end)
    after
      Connection.stop(maintenance_pid)
    end

    # The resolved discrete keys, without :url - a configured url would win over the run's
    # database name. :ssl among them, normalized, so every connection opened afterwards
    # reaches the server the way the bootstrap's did.
    Application.put_env(
      :hologram,
      :database,
      Keyword.put(database_opts, :database, run_databases[database_opts[:database]])
    )

    :persistent_term.put(@ran_key, true)

    run_databases
  end

  @doc """
  Returns the name of the run database a run with the given id makes for the given configured
  database.
  """
  @spec run_database_name(String.t(), String.t()) :: String.t()
  # Fitted rather than concatenated: PostgreSQL truncates an over-long identifier to 63 bytes
  # without saying so, and a configured name at the limit would lose the run's suffix, so every
  # run would get the same name.
  def run_database_name(database, run_id) do
    Mapper.fit_identifier([database], [], "run_" <> run_id)
  end

  @doc """
  Runs run!/1 with no extra databases when the app declares entities and this VM hasn't run it
  yet, so a test helper that ran it first, for databases of its own beside the configured one,
  keeps the ones it got.

  An app without entities starts no database, so it needs no server.

  Refuses outside the test environment when it would run run!/1, naming Hologram.Test.setup/0,
  its caller.
  """
  @spec run_once!() :: :ok
  def run_once! do
    if Model.exists?() and not :persistent_term.get(@ran_key, false) do
      refuse_outside_test!(
        "Hologram.Test.setup/0 gives an app with entities a database of its own for the test " <>
          "run, which it creates and points the database config at",
        "setup/0"
      )

      run!()
    end

    :ok
  end

  # No handshake timeout: the handshake starts once the server accepted the TCP connection,
  # and a server that is up either finishes it, however long its cold start takes, or closes
  # the socket. The TCP connect itself keeps the driver's timeout. No ping timeout either, for the
  # same reason: a ping left unanswered for the driver's 15 s would stop the connection, and
  # through the link the whole run - the held connections live as long as it does, and the
  # maintenance one sits idle while they connect. The pings themselves stay, since they keep the
  # session from idling out on a server that sets idle_session_timeout.
  defp connection_opts(database_opts, database) do
    database_opts
    |> Config.postgrex_opts()
    |> Keyword.merge(database: database, handshake_timeout: :infinity, ping_timeout: :infinity)
  end

  # IF EXISTS: another run's sweep, or a test dropping its own databases, may have got there
  # first.
  defp drop_database_if_exists!(maintenance_pid, database) do
    quoted_database = Mapper.quote_identifier(database)
    Connection.query!(maintenance_pid, "DROP DATABASE IF EXISTS #{quoted_database}")
  end

  # The shadow verifier's scratch database goes too: a run killed while it verified leaves
  # one, and with run names never repeating, the verifier's own drop of a stale one never
  # reaches it. Dropped first, so a sweep stopped between the two drops leaves the mark for a
  # later one to find both by. Without FORCE, so a session the listing missed is never ended:
  # a database someone connected to since is left for a later run.
  defp drop_leftover_database!(maintenance_pid, database) do
    drop_database_if_exists!(maintenance_pid, ShadowVerifier.shadow_database_name(database))
    drop_database_if_exists!(maintenance_pid, database)
  rescue
    error in Postgrex.Error ->
      case error do
        %Postgrex.Error{postgres: %{code: :object_in_use}} -> :ok
        _other -> reraise error, __STACKTRACE__
      end
  end

  # A database whose connection failed is dropped at once: it never got the mark, so no later
  # run would drop it.
  defp hold_database!(maintenance_pid, database_opts, database) do
    connection_result =
      database_opts
      |> connection_opts(database)
      |> Connection.start()

    case connection_result do
      {:ok, connection_pid} ->
        quoted_database = Mapper.quote_identifier(database)
        Connection.query!(connection_pid, "COMMENT ON DATABASE #{quoted_database} IS '#{@mark}'")

        :ok

      # Raised in after, so the connect error is what the caller sees even when the drop fails.
      {:error, reason} ->
        try do
          drop_database_if_exists!(maintenance_pid, database)
        after
          raise reason
        end
    end
  end

  # Only the databases the configured role owns, since it can drop no others. A database
  # someone is connected to is left out: dropping one waits several seconds for its sessions
  # before it fails.
  defp list_leftover_databases(maintenance_pid) do
    statement = """
    SELECT "datname" FROM pg_catalog.pg_database AS "d"
    WHERE pg_catalog.shobj_description("d"."oid", 'pg_database') = '#{@mark}'
      AND "d"."datdba" = (SELECT "oid" FROM pg_catalog.pg_roles WHERE "rolname" = current_user)
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_stat_activity AS "a" WHERE "a"."datid" = "d"."oid"
      )
    """

    %{rows: rows} = Connection.query!(maintenance_pid, statement)

    Enum.map(rows, fn [database] -> database end)
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
      * TLS failed - with ssl set, the server may not offer TLS, or may present a \
    certificate the configured CA or host name doesn't match
      * the "postgres" maintenance database is missing - this bootstrap connects to it \
    to create the test databases

    Override the connection settings with config :hologram, :database in config/test.exs.
    """)
  end

  # The prod path this closes is one line in a release console: the :test atom passed to
  # Config.resolve!/2 supplies defaults only, so the app's real config wins, and the run's
  # databases would be created on whatever server it names, with the running app's config
  # repointed at them and the marked databases nobody is connected to dropped. A release with
  # no HOLOGRAM_ENV reports :dev, so it refuses. Named after the function the caller called, so a
  # test helper calling setup/0 too early is told to move that call.
  defp refuse_outside_test!(action, function) do
    env = Hologram.env()

    if env != :test do
      raise "#{action}, so it runs in the test env only - the current env is #{inspect(env)}. " <>
              "When neither HOLOGRAM_ENV nor MIX_ENV is set, the test env is recognized by the " <>
              "running ExUnit server, so call #{function} after ExUnit.start()."
    end
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
