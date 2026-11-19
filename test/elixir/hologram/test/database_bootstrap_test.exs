defmodule Hologram.Test.DatabaseBootstrapTest do
  # async: false - the tests mutate the HOLOGRAM_ENV variable and the :hologram app's
  # :database config, both BEAM-global.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Test.DatabaseBootstrap

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler

  @claim %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-10-23 12:00:00.000000Z]
  }

  # The configured database is the one the running suite depends on, so every test points
  # the bootstrap at the test's own scratch database instead. The config is restored before
  # the case template drops that database: on_exit callbacks run in reverse order of
  # registration, and the template registers its drop first.
  setup %{scratch_opts: scratch_opts} do
    original_config = Application.get_env(:hologram, :database)
    original_env = System.get_env("HOLOGRAM_ENV")

    Application.put_env(:hologram, :database, database: scratch_opts[:database])

    on_exit(fn ->
      if original_config do
        Application.put_env(:hologram, :database, original_config)
      else
        Application.delete_env(:hologram, :database)
      end

      if original_env do
        System.put_env("HOLOGRAM_ENV", original_env)
      else
        System.delete_env("HOLOGRAM_ENV")
      end
    end)

    :ok
  end

  defp accept_connections(listen_socket, upstream_opts, delay_ms, test_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        send(test_pid, :proxy_connection_accepted)

        forwarder =
          spawn_link(fn -> forward_connection(client_socket, upstream_opts, delay_ms) end)

        :ok = :gen_tcp.controlling_process(client_socket, forwarder)
        send(forwarder, :socket_handed_over)

        accept_connections(listen_socket, upstream_opts, 0, test_pid)

      # The listen socket closes with the test process that owns it.
      {:error, :closed} ->
        :ok
    end
  end

  defp claim(scratch, context) do
    route(scratch, fn -> SchemaReconciler.ensure_managed!(context) end)
  end

  defp database_exists?(scratch, database) do
    statement = "SELECT 1 FROM pg_catalog.pg_database WHERE datname = $1"

    %{rows: rows} = Postgrex.query!(scratch, statement, [database])

    rows != []
  end

  # Drops the database when the test exits, whether it passed or failed. The connection
  # options come from the scratch database's: by exit time the config may name a proxy that
  # died with the test.
  defp drop_database_on_exit(scratch_opts, database) do
    maintenance_opts = Keyword.put(scratch_opts, :database, "postgres")

    on_exit(fn ->
      {:ok, connection} = Postgrex.start_link(maintenance_opts)

      quoted_database = Mapper.quote_identifier(database)
      drop_statement = "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)"

      Postgrex.query!(connection, drop_statement, [])
      GenServer.stop(connection)
    end)
  end

  defp forward_connection(client_socket, upstream_opts, delay_ms) do
    receive do
      :socket_handed_over -> :ok
    end

    Process.sleep(delay_ms)

    {:ok, upstream_socket} =
      upstream_opts[:hostname]
      |> String.to_charlist()
      |> :gen_tcp.connect(upstream_opts[:port], [:binary, active: true])

    :ok = :inet.setopts(client_socket, active: true)

    relay(client_socket, upstream_socket)
  end

  defp hologram_schemas(scratch) do
    statement = """
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname IN ('hologram_data', 'hologram_system')
    ORDER BY nspname
    """

    %{rows: rows} = Postgrex.query!(scratch, statement, [])

    Enum.map(rows, fn [name] -> name end)
  end

  # Either side closing ends the relay normally, which closes the other side too: the bootstrap
  # stops its maintenance connection while the test still runs, and a crash would take the
  # linked test process down.
  defp relay(client_socket, upstream_socket) do
    receive do
      {:tcp, ^client_socket, data} ->
        :gen_tcp.send(upstream_socket, data)
        relay(client_socket, upstream_socket)

      {:tcp, ^upstream_socket, data} ->
        :gen_tcp.send(client_socket, data)
        relay(client_socket, upstream_socket)

      {:tcp_closed, _socket} ->
        :ok
    end
  end

  # Runs the bootstrap and drops the databases it created when the test exits.
  defp run_and_drop!(scratch_opts, extra_databases \\ []) do
    run_databases = run!(extra_databases)

    Enum.each(run_databases, fn {_database, run_database} ->
      drop_database_on_exit(scratch_opts, run_database)
    end)

    run_databases
  end

  # A TCP proxy in front of the given server that holds the first connection it accepts for
  # the given time before forwarding it, the way a server just started answers its first
  # connection, and forwards later ones at once. Sends the calling process
  # :proxy_connection_accepted for each connection it accepts. Returns the port it listens on.
  defp start_slow_first_connection_proxy(upstream_opts, delay_ms) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)
    test_pid = self()

    spawn_link(fn -> accept_connections(listen_socket, upstream_opts, delay_ms, test_pid) end)

    port
  end

  describe "run!/1" do
    test "leaves the tables of a run in progress alone", %{scratch_opts: scratch_opts} do
      run!()

      first_run_database = Config.connection_opts()[:database]
      drop_database_on_exit(scratch_opts, first_run_database)

      first_run_opts = Keyword.put(scratch_opts, :database, first_run_database)
      first_run = start_supervised!({Postgrex, first_run_opts}, id: :first_run)

      Postgrex.query!(first_run, ~s(CREATE SCHEMA IF NOT EXISTS "hologram_data"), [])
      Postgrex.query!(first_run, ~s{CREATE TABLE "hologram_data"."kept" ("id" integer)}, [])

      # A second run starts from the same config the first one did.
      Application.put_env(:hologram, :database, database: scratch_opts[:database])

      run!()

      drop_database_on_exit(scratch_opts, Config.connection_opts()[:database])

      %{rows: [[regclass]]} =
        Postgrex.query!(first_run, ~s[SELECT to_regclass('"hologram_data"."kept"')::text], [])

      assert regclass == "hologram_data.kept"
    end

    test "points the database config at a database of the run's own, named after the configured one",
         %{scratch: scratch, scratch_opts: scratch_opts} do
      scratch_database = scratch_opts[:database]

      assert %{^scratch_database => run_database} = run_and_drop!(scratch_opts)

      assert String.starts_with?(run_database, scratch_database <> "_run_")
      assert database_exists?(scratch, run_database)

      run_connection =
        start_supervised!({Postgrex, Keyword.put(scratch_opts, :database, run_database)},
          id: :run_connection
        )

      assert hologram_schemas(run_connection) == []

      expected_opts =
        scratch_opts
        |> Keyword.put(:database, run_database)
        |> Enum.sort()

      assert Enum.sort(Config.connection_opts()) == expected_opts
    end

    test "gives each run databases of its own", %{scratch_opts: scratch_opts} do
      first_run_databases = run_and_drop!(scratch_opts)

      Application.put_env(:hologram, :database, database: scratch_opts[:database])

      second_run_databases = run_and_drop!(scratch_opts)

      assert first_run_databases[scratch_opts[:database]] !=
               second_run_databases[scratch_opts[:database]]
    end

    test "creates a database of the run's own for each given name", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      given_database = scratch_opts[:database] <> "_given"

      run_databases = run_and_drop!(scratch_opts, [given_database])

      prepared_databases =
        run_databases
        |> Map.keys()
        |> Enum.sort()

      assert prepared_databases == Enum.sort([scratch_opts[:database], given_database])

      assert String.starts_with?(run_databases[given_database], given_database <> "_run_")
      assert database_exists?(scratch, run_databases[given_database])
    end

    test "replaces the database a configured url names", %{scratch_opts: scratch_opts} do
      url =
        "postgres://#{scratch_opts[:username]}:#{scratch_opts[:password]}@" <>
          "#{scratch_opts[:hostname]}:#{scratch_opts[:port]}/#{scratch_opts[:database]}"

      Application.put_env(:hologram, :database, url: url)

      run_databases = run_and_drop!(scratch_opts)

      assert Config.connection_opts()[:database] == run_databases[scratch_opts[:database]]
    end

    test "leaves the configured database alone", %{scratch: scratch, scratch_opts: scratch_opts} do
      claim(scratch, @claim)

      run!()

      drop_database_on_exit(scratch_opts, Config.connection_opts()[:database])

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "waits for a server slow to answer its first connection", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      # DBConnection's pool drops a request queued for a connection still opening about 6 s
      # after the pool starts (the third poll of its default 2 s queue interval), so a shorter
      # hold would not tell a connection that waits from one that gives up.
      proxy_port = start_slow_first_connection_proxy(scratch_opts, 8_000)

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: proxy_port
      )

      run_databases = run_and_drop!(scratch_opts)

      # One connection to the maintenance database, one held to the run's database.
      assert_received :proxy_connection_accepted
      assert_received :proxy_connection_accepted
      refute_received :proxy_connection_accepted

      assert database_exists?(scratch, run_databases[scratch_opts[:database]])
    end

    test "refuses to run outside the test env" do
      System.put_env("HOLOGRAM_ENV", "dev")

      expected_msg =
        "Hologram.Test.DatabaseBootstrap.run!/1 creates databases and points the " <>
          "database config at them, so it runs in the test env only - the current env " <>
          "is :dev. When neither HOLOGRAM_ENV nor MIX_ENV is set, the test env " <>
          "is recognized by the running ExUnit server, so call run!/1 after ExUnit.start()."

      assert_error RuntimeError, expected_msg, fn -> run!() end
    end
  end
end
