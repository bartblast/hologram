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

  # Drops the database when the test exits, whether it passed or failed.
  defp drop_database_on_exit(database) do
    on_exit(fn ->
      maintenance_opts = Config.connection_opts(database: "postgres")
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
  # stops its connections while the test still runs, and a crash would take the linked test
  # process down.
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
    test "returns :ok on a database holding no Hologram schemas", %{scratch: scratch} do
      assert run!() == :ok

      assert hologram_schemas(scratch) == []
    end

    test "creates the configured database and the given ones when absent", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      configured_database = scratch_opts[:database] <> "_configured"
      given_database = scratch_opts[:database] <> "_given"

      drop_database_on_exit(configured_database)
      drop_database_on_exit(given_database)

      Application.put_env(:hologram, :database, database: configured_database)

      run!([given_database])

      assert database_exists?(scratch, configured_database)
      assert database_exists?(scratch, given_database)
    end

    test "leaves an existing database in place", %{scratch: scratch} do
      Postgrex.query!(scratch, ~s{CREATE TABLE "public"."kept" ("id" integer)}, [])

      run!()

      %{rows: [[regclass]]} =
        Postgrex.query!(scratch, ~s[SELECT to_regclass('"public"."kept"')::text], [])

      assert regclass == "kept"
    end

    test "waits for a server slow to answer its first connection", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, @claim)

      # DBConnection's pool drops a request queued for a connection still opening about 6 s
      # after the pool starts (the third poll of its default 2 s queue interval), so a shorter
      # hold would not tell a connection that waits from one that gives up.
      proxy_port = start_slow_first_connection_proxy(scratch_opts, 8_000)

      Application.put_env(:hologram, :database,
        database: scratch_opts[:database],
        port: proxy_port
      )

      assert run!() == :ok

      # One connection to the maintenance database, one to the scratch database.
      assert_received :proxy_connection_accepted
      assert_received :proxy_connection_accepted
      refute_received :proxy_connection_accepted

      assert hologram_schemas(scratch) == []
    end

    test "drops the Hologram schemas of a database this app's test env has claimed", %{
      scratch: scratch
    } do
      claim(scratch, @claim)

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]

      run!()

      assert hologram_schemas(scratch) == []
    end

    test "drops the Hologram schemas of a database holding them without a marker table", %{
      scratch: scratch
    } do
      Postgrex.query!(scratch, ~s(CREATE SCHEMA "hologram_system"), [])
      Postgrex.query!(scratch, ~s(CREATE SCHEMA "hologram_data"), [])

      run!()

      assert hologram_schemas(scratch) == []
    end

    test "drops the Hologram schemas of a database whose marker table holds no row", %{
      scratch: scratch
    } do
      claim(scratch, @claim)
      Postgrex.query!(scratch, ~s(DELETE FROM "hologram_system"."database"), [])

      run!()

      assert hologram_schemas(scratch) == []
    end

    test "refuses a database another app has claimed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | otp_app: "other_app"})

      expected_msg =
        ~s(database "#{scratch_opts[:database]}" belongs to the "test" env of app ) <>
          ~s("other_app" - Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's ) <>
          "schemas only in a database nothing has claimed or the \"test\" env of app " <>
          "\"hologram\" has claimed - point the test env's config :hologram, :database " <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> run!() end

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "refuses a database another env has claimed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | env: "dev"})

      expected_msg =
        ~s(database "#{scratch_opts[:database]}" belongs to the "dev" env of app ) <>
          ~s("hologram" - Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's ) <>
          "schemas only in a database nothing has claimed or the \"test\" env of app " <>
          "\"hologram\" has claimed - point the test env's config :hologram, :database " <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> run!() end

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "refuses a given database another env has claimed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | env: "dev"})

      # The configured database is one the bootstrap creates, so the refusal can only come
      # from the given one.
      configured_database = scratch_opts[:database] <> "_configured"
      drop_database_on_exit(configured_database)

      Application.put_env(:hologram, :database, database: configured_database)

      expected_msg =
        ~s(database "#{scratch_opts[:database]}" belongs to the "dev" env of app ) <>
          ~s("hologram" - Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's ) <>
          "schemas only in a database nothing has claimed or the \"test\" env of app " <>
          "\"hologram\" has claimed - point the test env's config :hologram, :database " <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> run!([scratch_opts[:database]]) end

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "refuses to run outside the test env" do
      System.put_env("HOLOGRAM_ENV", "dev")

      expected_msg =
        "Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's schemas and runs " <>
          "in the test env only - the current env is :dev. When neither " <>
          "HOLOGRAM_ENV nor MIX_ENV is set, the test env is recognized by the " <>
          "running ExUnit server, so call run!/1 after ExUnit.start()."

      assert_error RuntimeError, expected_msg, fn -> run!() end
    end
  end
end
