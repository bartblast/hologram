defmodule Hologram.Test.DatabaseBootstrapTest do
  # async: false - the tests mutate the HOLOGRAM_ENV variable, the :hologram app's :database
  # config, the record of the bootstrap having run and the cached data model, all BEAM-global.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Test.DatabaseBootstrap

  alias Hologram.DB.Config
  alias Hologram.DB.Listener
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity.Model
  alias Hologram.Test.DatabaseBootstrap
  alias Hologram.Test.DatabaseBootstrap.Connection
  alias Hologram.Test.TLSProxy

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

  defp close_connections(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        :gen_tcp.close(client_socket)
        close_connections(listen_socket)

      # The listen socket closes with the test process that owns it.
      {:error, :closed} ->
        :ok
    end
  end

  # Opens a connection to the maintenance database through the given proxy, checking its
  # certificate under the given mode against the CA in the given file.
  defp connect_through(proxy, mode, ca_cert_path) do
    [
      database: "postgres",
      port: TLSProxy.port(proxy),
      ssl: [ca_cert_path: ca_cert_path, mode: mode]
    ]
    |> Config.resolve!(:test)
    |> Config.postgrex_opts()
    |> Connection.start()
  end

  defp create_database(scratch, database) do
    quoted_database = Mapper.quote_identifier(database)
    Postgrex.query!(scratch, "CREATE DATABASE #{quoted_database} TEMPLATE template0", [])
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

  # Runs the bootstrap in a process that is then shut down, the way a run ends, and returns the
  # databases it created once the server has ended their sessions. Shut down rather than left
  # to return: an exit :normal doesn't take the linked held connections down. The config is put
  # back for the next run.
  defp run_in_ended_process!(scratch, scratch_opts) do
    test_pid = self()

    run_pid =
      spawn(fn ->
        send(test_pid, {:run_databases, run!()})
        Process.sleep(:infinity)
      end)

    assert_receive {:run_databases, run_databases}, 10_000

    Enum.each(run_databases, fn {_database, run_database} ->
      drop_database_on_exit(scratch_opts, run_database)
    end)

    Process.exit(run_pid, :shutdown)

    ended_databases = Map.values(run_databases)

    wait_until(fn -> Enum.all?(ended_databases, &(session_count(scratch, &1) == 0)) end, 5_000)

    Application.put_env(:hologram, :database, database: scratch_opts[:database])

    run_databases
  end

  defp session_count(scratch, database) do
    statement = "SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE datname = $1"

    %{rows: [[count]]} = Postgrex.query!(scratch, statement, [database])

    count
  end

  # A TCP proxy in front of the given server that forwards the first connection it accepts and
  # closes every later one at once, the way a server that stops taking connections would.
  # Returns the port it listens on.
  defp start_first_connection_only_proxy(upstream_opts) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)

    spawn_link(fn ->
      {:ok, client_socket} = :gen_tcp.accept(listen_socket)

      forwarder = spawn_link(fn -> forward_connection(client_socket, upstream_opts, 0) end)

      :ok = :gen_tcp.controlling_process(client_socket, forwarder)
      send(forwarder, :socket_handed_over)

      close_connections(listen_socket)
    end)

    port
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

    test "holds each run database with a connection that waits out a slow ping", %{
      scratch_opts: scratch_opts
    } do
      run_databases = run_and_drop!(scratch_opts)
      run_database = run_databases[scratch_opts[:database]]

      {:links, linked_pids} = Process.info(self(), :links)

      [held_connection] =
        Enum.filter(linked_pids, fn pid ->
          :proc_lib.get_label(pid) == {Postgrex.Protocol, run_database}
        end)

      {_state_name, state} = :sys.get_state(held_connection)

      assert state.protocol.ping_timeout == :infinity
    end

    test "marks the run's databases", %{scratch: scratch, scratch_opts: scratch_opts} do
      run_databases = run_and_drop!(scratch_opts, [scratch_opts[:database] <> "_given"])

      statement = """
      SELECT pg_catalog.shobj_description("oid", 'pg_database')
      FROM pg_catalog.pg_database
      WHERE "datname" = $1
      """

      Enum.each(run_databases, fn {_database, run_database} ->
        assert Postgrex.query!(scratch, statement, [run_database]).rows == [[mark()]]
      end)
    end

    test "drops a run database nothing is connected to", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      ended_run_databases = run_in_ended_process!(scratch, scratch_opts)

      run_and_drop!(scratch_opts)

      refute database_exists?(scratch, ended_run_databases[scratch_opts[:database]])
    end

    test "drops the shadow verifier's database named after a run database it drops", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      ended_run_databases = run_in_ended_process!(scratch, scratch_opts)

      shadow_database =
        Mapper.fit_identifier([ended_run_databases[scratch_opts[:database]]], [], "shadow")

      create_database(scratch, shadow_database)
      drop_database_on_exit(scratch_opts, shadow_database)

      run_and_drop!(scratch_opts)

      refute database_exists?(scratch, shadow_database)
    end

    test "leaves a run database a run is connected to alone, without waiting on it", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      first_run_databases = run_and_drop!(scratch_opts)

      Application.put_env(:hologram, :database, database: scratch_opts[:database])

      {elapsed_us, _run_databases} = :timer.tc(fn -> run_and_drop!(scratch_opts) end)

      assert database_exists?(scratch, first_run_databases[scratch_opts[:database]])

      # Dropping a database someone is connected to fails only after the server has waited 5 s
      # for its sessions to end, so a run that tried would take longer than that.
      assert elapsed_us < 5_000_000
    end

    test "drops a run database whose connection failed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      run_database_prefix = scratch_opts[:database] <> "_run_"
      maintenance_opts = Keyword.put(scratch_opts, :database, "postgres")

      # The run database's name is random, so should it be left behind, it's found by prefix.
      on_exit(fn ->
        {:ok, connection} = Postgrex.start_link(maintenance_opts)

        %{rows: rows} =
          Postgrex.query!(
            connection,
            "SELECT datname FROM pg_catalog.pg_database WHERE starts_with(datname, $1)",
            [run_database_prefix]
          )

        Enum.each(rows, fn [database] ->
          quoted_database = Mapper.quote_identifier(database)

          Postgrex.query!(
            connection,
            "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)",
            []
          )
        end)

        GenServer.stop(connection)
      end)

      # The maintenance connection gets through, the run database's own connection doesn't.
      proxy_port = start_first_connection_only_proxy(scratch_opts)

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: proxy_port
      )

      log =
        capture_log(fn ->
          assert_raise DBConnection.ConnectionError, fn -> run!() end
        end)

      assert log =~ "failed to connect to Postgres"

      statement = "SELECT datname FROM pg_catalog.pg_database WHERE starts_with(datname, $1)"

      assert Postgrex.query!(scratch, statement, [run_database_prefix]).rows == []
    end

    test "leaves a database without the mark alone", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      unmarked_database = scratch_opts[:database] <> "_unmarked"

      create_database(scratch, unmarked_database)
      drop_database_on_exit(scratch_opts, unmarked_database)

      run_and_drop!(scratch_opts)

      assert database_exists?(scratch, unmarked_database)
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
        "Hologram.Test.DatabaseBootstrap.run!/1 creates and drops databases and points " <>
          "the database config at them, so it runs in the test env only - the current env " <>
          "is :dev. When neither HOLOGRAM_ENV nor MIX_ENV is set, the test env " <>
          "is recognized by the running ExUnit server, so call run!/1 after ExUnit.start()."

      assert_error RuntimeError, expected_msg, fn -> run!() end
    end
  end

  describe "TLS" do
    test "run!/1 reaches the server through TLS when the config sets ssl, checking its certificate",
         %{scratch_opts: scratch_opts} do
      proxy = start_supervised!(TLSProxy)
      ssl = [ca_cert_path: TLSProxy.ca_cert_path(proxy), mode: :verify_full]

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: TLSProxy.port(proxy),
        ssl: ssl
      )

      run_and_drop!(scratch_opts)

      # One connection to the maintenance database, one held to the run's database.
      assert TLSProxy.tls_sessions(proxy) == 2
      assert TLSProxy.plain_sessions(proxy) == 0

      assert Application.get_env(:hologram, :database)[:ssl] == ssl
    end

    test "run!/1 presents the client certificate the config sets", %{scratch_opts: scratch_opts} do
      proxy = start_supervised!({TLSProxy, client_cert: true})

      ssl =
        [ca_cert_path: TLSProxy.ca_cert_path(proxy), mode: :verify_full] ++
          TLSProxy.client_cert_paths(proxy)

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: TLSProxy.port(proxy),
        ssl: ssl
      )

      run_and_drop!(scratch_opts)

      assert TLSProxy.client_cert_sessions(proxy) == 2
    end

    test "a held connection reaches the server through TLS when the config sets ssl", %{
      scratch_opts: scratch_opts
    } do
      proxy = start_supervised!(TLSProxy)

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        ssl: [ca_cert_path: TLSProxy.ca_cert_path(proxy), mode: :verify_full]
      )

      start_supervised!(
        Supervisor.child_spec(
          {Listener, port: TLSProxy.port(proxy), sync_connect: true},
          restart: :temporary
        )
      )

      assert TLSProxy.tls_sessions(proxy) == 1
      assert TLSProxy.plain_sessions(proxy) == 0
    end

    test "run!/1 under mode :verify_ca accepts a certificate for another host", %{
      scratch_opts: scratch_opts
    } do
      proxy = start_supervised!({TLSProxy, cert: :other_host})

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: TLSProxy.port(proxy),
        ssl: [ca_cert_path: TLSProxy.ca_cert_path(proxy), mode: :verify_ca]
      )

      run_and_drop!(scratch_opts)

      assert TLSProxy.tls_sessions(proxy) == 2
    end

    test "run!/1 under mode :verify_ca accepts a certificate with no subjectAltName", %{
      scratch_opts: scratch_opts
    } do
      proxy = start_supervised!({TLSProxy, cert: :common_name_only})

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: TLSProxy.port(proxy),
        ssl: [ca_cert_path: TLSProxy.ca_cert_path(proxy), mode: :verify_ca]
      )

      run_and_drop!(scratch_opts)

      assert TLSProxy.tls_sessions(proxy) == 2
    end

    test "mode :verify_ca refuses a certificate its CA didn't sign" do
      proxy = start_supervised!(TLSProxy)
      other_proxy = start_supervised!(TLSProxy, id: :other_proxy)

      capture_log(fn ->
        assert {:error, %DBConnection.ConnectionError{message: message}} =
                 connect_through(proxy, :verify_ca, TLSProxy.ca_cert_path(other_proxy))

        assert message =~ "Unknown CA"
      end)
    end

    test "mode :verify_full refuses a certificate for another host" do
      proxy = start_supervised!({TLSProxy, cert: :other_host})

      capture_log(fn ->
        assert {:error, %DBConnection.ConnectionError{message: message}} =
                 connect_through(proxy, :verify_full, TLSProxy.ca_cert_path(proxy))

        assert message =~ "hostname_check_failed"
      end)
    end

    test "mode :verify_full refuses a certificate with no subjectAltName for another host" do
      proxy = start_supervised!({TLSProxy, cert: :common_name_only})

      capture_log(fn ->
        assert {:error, %DBConnection.ConnectionError{message: message}} =
                 connect_through(proxy, :verify_full, TLSProxy.ca_cert_path(proxy))

        assert message =~ "hostname_check_failed"
      end)
    end
  end

  describe "run_once!/0" do
    # The suite's helper ran the bootstrap, so the record of it is put back for the tests after.
    setup do
      ran_key = {DatabaseBootstrap, :ran}
      original_ran = :persistent_term.get(ran_key, nil)

      on_exit(fn ->
        if original_ran do
          :persistent_term.put(ran_key, original_ran)
        else
          :persistent_term.erase(ran_key)
        end
      end)

      %{ran_key: ran_key}
    end

    test "creates the run's database when the app declares entities and this VM has none yet",
         %{ran_key: ran_key, scratch: scratch, scratch_opts: scratch_opts} do
      :persistent_term.erase(ran_key)

      assert run_once!() == :ok

      run_database = Config.connection_opts()[:database]
      drop_database_on_exit(scratch_opts, run_database)

      assert String.starts_with?(run_database, scratch_opts[:database] <> "_run_")
      assert database_exists?(scratch, run_database)
    end

    test "keeps the run's databases when this VM made them already", %{scratch_opts: scratch_opts} do
      run_and_drop!(scratch_opts)
      Application.put_env(:hologram, :database, database: scratch_opts[:database])

      assert run_once!() == :ok

      assert Application.get_env(:hologram, :database) == [database: scratch_opts[:database]]
    end

    test "creates no database when the app declares no entities", %{
      ran_key: ran_key,
      scratch_opts: scratch_opts
    } do
      :persistent_term.erase(ran_key)
      Model.put_facts([], [], nil)
      on_exit(&Model.reset_caches/0)

      assert run_once!() == :ok

      assert Application.get_env(:hologram, :database) == [database: scratch_opts[:database]]
    end

    test "refuses to run outside the test env, naming setup/0", %{ran_key: ran_key} do
      :persistent_term.erase(ran_key)
      System.put_env("HOLOGRAM_ENV", "dev")

      expected_msg =
        "Hologram.Test.setup/0 gives an app with entities a database of its own for the test " <>
          "run, which it creates and points the database config at, so it runs in the test env " <>
          "only - the current env is :dev. When neither HOLOGRAM_ENV nor MIX_ENV is set, the " <>
          "test env is recognized by the running ExUnit server, so call setup/0 after " <>
          "ExUnit.start()."

      assert_error RuntimeError, expected_msg, fn -> run_once!() end
    end
  end
end
