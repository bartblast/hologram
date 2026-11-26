defmodule Hologram.DB.ConfigTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Config

  describe "connection_opts/1" do
    test "returns the configured database as Postgrex options" do
      opts = connection_opts()

      # The database bootstrap points the config at a database of the run's own, named after
      # the configured one. A run excluding the database tests doesn't run the bootstrap.
      assert opts[:database] =~ ~r/\Ahologram_test(_run_[0-9a-f]{8})?\z/
      assert opts[:hostname] == "localhost"
      assert opts[:password] == "postgres"
      assert opts[:port] == 5432
      assert opts[:username] == "postgres"
    end

    test "applies the given overrides" do
      assert connection_opts(database: "other")[:database] == "other"
    end

    test "carries the configured ssl" do
      assert Keyword.fetch(connection_opts(), :ssl) == {:ok, false}
    end
  end

  describe "first_statement_timeout_ms/0" do
    # A session-mode PgBouncer queues a session's first statement until a server connection frees,
    # and ends the wait itself after query_wait_timeout by closing the session - the connection logs
    # that as lost, where the kill logs nothing.
    test "outlasts PgBouncer's default query_wait_timeout of 120 seconds" do
      assert first_statement_timeout_ms() > :timer.seconds(120)
    end
  end

  describe "held_connection_opts/1" do
    test "returns the configured database's options for a connection that waits for it" do
      opts = held_connection_opts()

      assert opts[:database] == connection_opts()[:database]
      assert opts[:auto_reconnect] == true
      assert opts[:idle_interval] == 5_000
      assert opts[:reconnect_backoff] == 2_000
      assert opts[:sync_connect] == false
    end

    test "carries the configured ssl" do
      assert Keyword.fetch(held_connection_opts(), :ssl) == {:ok, false}
    end

    test "applies the given overrides" do
      opts = held_connection_opts(name: :my_connection, reconnect_backoff: 50, port: 6543)

      assert opts[:name] == :my_connection
      assert opts[:reconnect_backoff] == 50
      assert opts[:port] == 6543
    end

    # A call arriving between two tries arms the idle ping, which crashes on the missing socket if
    # it fires before the next try.
    test "raises when the backoff is not below the idle interval" do
      assert_raise ArgumentError,
                   "the reconnect backoff of a held connection must be below its idle interval, got 5000 ms and 5000 ms",
                   fn -> held_connection_opts(reconnect_backoff: 5_000) end

      assert_raise ArgumentError, fn ->
        held_connection_opts(reconnect_backoff: 100, idle_interval: 100)
      end
    end
  end

  describe "postgrex_opts/1" do
    @resolved [
      database: "my_db",
      host: "db.example.com",
      password: "secret",
      pool_size: 25,
      port: 6543,
      ssl: false,
      user: "alice"
    ]

    test "turns the resolved options into Postgrex options, without the pool size" do
      assert postgrex_opts(@resolved) == [
               database: "my_db",
               hostname: "db.example.com",
               password: "secret",
               port: 6543,
               ssl: false,
               username: "alice"
             ]
    end

    test "encrypts without checking the certificate under the require mode" do
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, mode: :require))

      assert opts[:ssl] == [verify: :verify_none]
    end

    # The server name still goes out in the handshake: no server_name_indication: :disable,
    # which would drop it along with the host name check.
    test "checks the certificate against the system's CAs, not the host name, under the verify_ca mode" do
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, mode: :verify_ca))
      system_cacerts = :public_key.cacerts_get()

      assert [verify: :verify_peer, verify_fun: {verify_fun, nil}, cacerts: ^system_cacerts] =
               opts[:ssl]

      assert verify_fun.(:cert, {:bad_cert, :hostname_check_failed}, nil) == {:valid, nil}
    end

    test "checks the certificate against the given CA under the verify_ca mode" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_ca]
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))

      assert [verify: :verify_peer, verify_fun: {verify_fun, nil}, cacertfile: "/certs/ca.pem"] =
               opts[:ssl]

      assert verify_fun.(:cert, {:bad_cert, :hostname_check_failed}, nil) == {:valid, nil}
    end

    # The clauses of the fun the ssl application wraps a one-argument verify_fun in.
    test "keeps the ssl application's handling of every other certificate event under the verify_ca mode" do
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, mode: :verify_ca))
      {verify_fun, state} = opts[:ssl][:verify_fun]

      assert verify_fun.(:cert, {:bad_cert, :unknown_ca}, state) ==
               {:fail, {:bad_cert, :unknown_ca}}

      assert verify_fun.(:cert, {:extension, :an_extension}, state) == {:unknown, state}
      assert verify_fun.(:cert, :valid, state) == {:valid, state}
      assert verify_fun.(:cert, :valid_peer, state) == {:valid, state}
    end

    # The ssl application's default verify_fun renames an expired trust anchor's failure, so that
    # it looks for a cross-signed root in its place.
    test "fails an expired self-signed certificate as an expired root under the verify_ca mode" do
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, mode: :verify_ca))
      {verify_fun, state} = opts[:ssl][:verify_fun]

      root = :public_key.pkix_test_root_cert(~c"Test Root", [])

      peer =
        :public_key.pkix_test_data(%{
          server_chain: %{root: root, intermediates: [], peer: []},
          client_chain: %{root: [], intermediates: [], peer: []}
        })[:server_config][:cert]

      root_cert = :public_key.pkix_decode_cert(root.cert, :otp)
      peer_cert = :public_key.pkix_decode_cert(peer, :otp)

      assert verify_fun.(root_cert, {:bad_cert, :cert_expired}, state) ==
               {:fail, {:bad_cert, :root_cert_expired}}

      assert verify_fun.(peer_cert, {:bad_cert, :cert_expired}, state) ==
               {:fail, {:bad_cert, :cert_expired}}
    end

    # Postgrex adds the host name check to a list itself.
    test "checks the certificate against the system's CAs under the verify_full mode" do
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, mode: :verify_full))

      assert opts[:ssl] == [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
    end

    test "checks the certificate against the given CA under the verify_full mode" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_full]
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))

      assert opts[:ssl] == [verify: :verify_peer, cacertfile: "/certs/ca.pem"]
    end

    test "presents the given client certificate" do
      ssl = [cert_path: "/certs/client.pem", key_path: "/certs/client.key", mode: :require]
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))

      assert opts[:ssl] == [
               verify: :verify_none,
               certfile: "/certs/client.pem",
               keyfile: "/certs/client.key"
             ]
    end

    test "presents the given client certificate alongside the given CA" do
      ssl = [
        ca_cert_path: "/certs/ca.pem",
        cert_path: "/certs/client.pem",
        key_path: "/certs/client.key",
        mode: :verify_full
      ]

      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))

      assert opts[:ssl] == [
               verify: :verify_peer,
               cacertfile: "/certs/ca.pem",
               certfile: "/certs/client.pem",
               keyfile: "/certs/client.key"
             ]
    end
  end

  describe "resolve!/2" do
    test "applies dev defaults when no config is given" do
      assert resolve!([], :dev) == [
               database: "hologram_dev",
               host: "localhost",
               password: "postgres",
               pool_size: 10,
               port: 5432,
               ssl: false,
               user: "postgres"
             ]
    end

    test "derives the default database name from the environment" do
      config = resolve!([], :test)

      assert config[:database] == "hologram_test"
    end

    test "overlays discrete keys on the environment defaults" do
      config = [
        database: "custom_db",
        host: "db.local",
        password: "secret",
        pool_size: 25,
        port: 6432,
        user: "alice"
      ]

      assert resolve!(config, :dev) == [
               database: "custom_db",
               host: "db.local",
               password: "secret",
               pool_size: 25,
               port: 6432,
               ssl: false,
               user: "alice"
             ]
    end

    test "overlays url components on discrete keys" do
      config = [
        host: "ignored.local",
        url: "postgres://alice:secret@db.example.com:6543/my_db"
      ]

      assert resolve!(config, :dev) == [
               database: "my_db",
               host: "db.example.com",
               password: "secret",
               pool_size: 10,
               port: 6543,
               ssl: false,
               user: "alice"
             ]
    end

    test "falls back for components absent from the url" do
      config = [url: "postgres://db.example.com/my_db"]

      assert resolve!(config, :dev) == [
               database: "my_db",
               host: "db.example.com",
               password: "postgres",
               pool_size: 10,
               port: 5432,
               ssl: false,
               user: "postgres"
             ]
    end

    test "defaults port and pool size when the environment has no identity defaults" do
      config = [
        database: "my_app",
        host: "db.example.com",
        password: "secret",
        user: "alice"
      ]

      assert resolve!(config, :prod) == [
               database: "my_app",
               host: "db.example.com",
               password: "secret",
               pool_size: 10,
               port: 5432,
               ssl: false,
               user: "alice"
             ]
    end

    test "satisfies the required keys from url components alone" do
      config = [url: "postgres://alice:secret@db.example.com:6543/my_app"]

      assert resolve!(config, :prod) == [
               database: "my_app",
               host: "db.example.com",
               password: "secret",
               pool_size: 10,
               port: 6543,
               ssl: false,
               user: "alice"
             ]
    end

    test "keeps ssl off when set to false" do
      assert resolve!([ssl: false], :dev)[:ssl] == false
    end

    test "turns ssl true into the verify_full mode" do
      assert resolve!([ssl: true], :dev)[:ssl] == [mode: :verify_full]
    end

    test "gives an ssl list without a mode the verify_full mode" do
      assert resolve!([ssl: []], :dev)[:ssl] == [mode: :verify_full]

      assert resolve!([ssl: [ca_cert_path: "/certs/ca.pem"]], :dev)[:ssl] == [
               ca_cert_path: "/certs/ca.pem",
               mode: :verify_full
             ]
    end

    test "keeps the given ssl mode" do
      for mode <- [:require, :verify_ca, :verify_full] do
        assert resolve!([ssl: [mode: mode]], :dev)[:ssl] == [mode: mode]
      end
    end

    test "sorts the ssl list by entry" do
      ssl = [
        mode: :verify_ca,
        key_path: "/certs/client.key",
        cert_path: "/certs/client.pem",
        ca_cert_path: "/certs/ca.pem"
      ]

      assert resolve!([ssl: ssl], :dev)[:ssl] == [
               ca_cert_path: "/certs/ca.pem",
               cert_path: "/certs/client.pem",
               key_path: "/certs/client.key",
               mode: :verify_ca
             ]
    end

    # The test bootstrap writes the resolved options back into the config, which is resolved
    # again from there.
    test "accepts its own resolved ssl" do
      ssl = [cert_path: "/certs/client.pem", key_path: "/certs/client.key", mode: :verify_ca]
      resolved = resolve!([ssl: ssl], :dev)

      assert resolve!(resolved, :dev) == resolved
    end

    test "leaves ssl to its key when a url is given" do
      config = [ssl: [mode: :require], url: "postgres://alice:secret@db.example.com/my_db"]

      assert resolve!(config, :dev)[:ssl] == [mode: :require]
    end

    test "raises on an ssl value other than a boolean or a keyword list" do
      for value <- [:verify_full, nil, ["mode"]] do
        expected_msg =
          "invalid ssl in config :hologram, :database - expected false, true or a keyword list, got: #{inspect(value)}"

        assert_error ArgumentError, expected_msg, fn -> resolve!([ssl: value], :dev) end
      end
    end

    test "raises on an unknown ssl entry" do
      expected_msg =
        "unknown ssl entry :cacertfile in config :hologram, :database - supported: :ca_cert_path, :cert_path, :key_path, :mode"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([ssl: [cacertfile: "/certs/ca.pem"]], :dev)
      end
    end

    test "raises on an unknown ssl mode" do
      expected_msg =
        "invalid ssl entry :mode in config :hologram, :database - expected :require, :verify_ca or :verify_full, got: :prefer"

      assert_error ArgumentError, expected_msg, fn -> resolve!([ssl: [mode: :prefer]], :dev) end
    end

    test "raises on an ssl path entry that is not a non-empty string" do
      for entry <- [:ca_cert_path, :cert_path, :key_path],
          value <- ["", nil, ~c"/certs/ca.pem"] do
        expected_msg =
          "invalid ssl entry #{inspect(entry)} in config :hologram, :database - expected a non-empty string, got: #{inspect(value)}"

        assert_error ArgumentError, expected_msg, fn ->
          resolve!([ssl: [{entry, value}]], :dev)
        end
      end
    end

    test "raises on a repeated ssl entry" do
      expected_msg =
        "ssl entry :mode in config :hologram, :database is given more than once"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([ssl: [mode: :require, mode: :verify_full]], :dev)
      end
    end

    # Mode :require doesn't check the server's certificate, so the CA would go unused.
    test "raises on a CA under the require mode" do
      expected_msg =
        "ssl entry :ca_cert_path in config :hologram, :database needs mode :verify_ca or :verify_full - mode :require doesn't check the server's certificate"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([ssl: [ca_cert_path: "/certs/ca.pem", mode: :require]], :dev)
      end
    end

    test "raises on a client certificate without its key" do
      expected_msg =
        "ssl entry :cert_path in config :hologram, :database needs :key_path, the key of the client certificate"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([ssl: [cert_path: "/certs/client.pem"]], :dev)
      end
    end

    test "raises on a client key without its certificate" do
      expected_msg =
        "ssl entry :key_path in config :hologram, :database needs :cert_path, the client certificate of the key"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([ssl: [key_path: "/certs/client.key"]], :dev)
      end
    end

    test "raises when identity keys are missing and the environment has no defaults" do
      expected_msg =
        "missing database configuration for :prod - set config :hologram, :database with discrete keys or url:, missing: database, password, user"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([host: "db.example.com"], :prod)
      end
    end
  end
end
