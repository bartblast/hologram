defmodule Hologram.DB.ConfigTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Config

  @url "postgres://alice:secret@db.example.com/my_db"

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
    test "checks the certificate against the given CA under the verify_ca mode" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_ca]
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))

      assert [verify: :verify_peer, verify_fun: {verify_fun, nil}, cacertfile: "/certs/ca.pem"] =
               opts[:ssl]

      assert verify_fun.(:cert, {:bad_cert, :hostname_check_failed}, nil) == {:valid, nil}
    end

    # The clauses of the fun the ssl application wraps a one-argument verify_fun in.
    test "keeps the ssl application's handling of every other certificate event under the verify_ca mode" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_ca]
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))
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
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_ca]
      opts = postgrex_opts(Keyword.put(@resolved, :ssl, ssl))
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

    test "percent-decodes the url's user, password and database" do
      config = [url: "postgres://al%69ce%3Aadmin:p%40ss%3Aw%2Bord+1@db.example.com/my%20db"]

      assert resolve!(config, :dev) == [
               database: "my db",
               host: "db.example.com",
               password: "p@ss:w+ord+1",
               pool_size: 10,
               port: 5432,
               ssl: false,
               user: "alice:admin"
             ]
    end

    test "raises on a malformed percent-encoding in the url's user, password or database" do
      for {url, component} <- [
            {"postgres://al%zzice:secret@db.example.com/my_db", "user"},
            {"postgres://alice:se%zcret@db.example.com/my_db", "password"},
            {"postgres://alice:secret%@db.example.com/my_db", "password"},
            {"postgres://alice:secret@db.example.com/my%2_db", "database"}
          ] do
        expected_msg =
          "invalid url #{component} in config :hologram, :database - malformed percent-encoding"

        assert_error ArgumentError, expected_msg, fn -> resolve!([url: url], :dev) end
      end
    end

    test "raises on an encoded zero byte in the url's user, password or database" do
      for {url, component} <- [
            {"postgres://al%00ice:secret@db.example.com/my_db", "user"},
            {"postgres://alice:se%00cret@db.example.com/my_db", "password"},
            {"postgres://alice:secret@db.example.com/my%00db", "database"}
          ] do
        expected_msg =
          "invalid url #{component} in config :hologram, :database - malformed percent-encoding"

        assert_error ArgumentError, expected_msg, fn -> resolve!([url: url], :dev) end
      end
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
      for mode <- [:require, :verify_full] do
        assert resolve!([ssl: [mode: mode]], :dev)[:ssl] == [mode: mode]
      end

      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_ca]

      assert resolve!([ssl: ssl], :dev)[:ssl] == ssl
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
      ssl = [
        ca_cert_path: "/certs/ca.pem",
        cert_path: "/certs/client.pem",
        key_path: "/certs/client.key",
        mode: :verify_ca
      ]

      resolved = resolve!([ssl: ssl], :dev)

      assert resolve!(resolved, :dev) == resolved
    end

    test "leaves ssl to its key when a url is given" do
      config = [ssl: [mode: :require], url: "postgres://alice:secret@db.example.com/my_db"]

      assert resolve!(config, :dev)[:ssl] == [mode: :require]
    end

    test "reads the url's sslmode" do
      for {sslmode, mode} <- [{"require", :require}, {"verify-full", :verify_full}] do
        assert resolve_url!("sslmode=#{sslmode}")[:ssl] == [mode: mode]
      end

      assert resolve_url!("sslmode=verify-ca&sslrootcert=/certs/ca.pem")[:ssl] == [
               ca_cert_path: "/certs/ca.pem",
               mode: :verify_ca
             ]
    end

    test "turns ssl off on the url's sslmode=disable" do
      assert resolve_url!("sslmode=disable")[:ssl] == false
    end

    test "reads the url's certificate parameters" do
      query =
        "sslmode=verify-ca&sslrootcert=/certs/ca.pem&sslcert=/certs/client.pem&sslkey=/certs/client.key"

      assert resolve_url!(query)[:ssl] == [
               ca_cert_path: "/certs/ca.pem",
               cert_path: "/certs/client.pem",
               key_path: "/certs/client.key",
               mode: :verify_ca
             ]
    end

    test "percent-decodes the url's parameters" do
      assert resolve_url!("sslmode=verify-full&sslrootcert=/my%20certs/ca+1.pem")[:ssl] == [
               ca_cert_path: "/my certs/ca+1.pem",
               mode: :verify_full
             ]
    end

    test "trusts the system's CAs on the url's sslrootcert=system" do
      assert resolve_url!("sslmode=verify-full&sslrootcert=system")[:ssl] == [mode: :verify_full]
    end

    test "accepts the url's channel_binding values Postgrex meets without binding" do
      for value <- ["disable", "prefer"] do
        assert resolve_url!("sslmode=require&channel_binding=#{value}")[:ssl] == [mode: :require]
      end
    end

    test "leaves ssl as it is for a url query without TLS parameters" do
      assert resolve_url!("", ssl: [mode: :require])[:ssl] == [mode: :require]
      assert resolve_url!("channel_binding=prefer")[:ssl] == false
    end

    test "has the url's sslmode replace only the key's mode" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_full]

      assert resolve_url!("sslmode=verify-ca", ssl: ssl)[:ssl] == [
               ca_cert_path: "/certs/ca.pem",
               mode: :verify_ca
             ]
    end

    test "has the url's sslrootcert replace only the key's ca_cert_path" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_ca]

      assert resolve_url!("sslrootcert=/certs/other.pem", ssl: ssl)[:ssl] == [
               ca_cert_path: "/certs/other.pem",
               mode: :verify_ca
             ]
    end

    test "has the url's sslrootcert=system replace the key's ca_cert_path" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_full]

      assert resolve_url!("sslrootcert=system", ssl: ssl)[:ssl] == [mode: :verify_full]
    end

    test "completes the key's client certificate with the url's sslkey" do
      ssl = [cert_path: "/certs/client.pem"]

      assert resolve_url!("sslkey=/certs/client.key", ssl: ssl)[:ssl] == [
               cert_path: "/certs/client.pem",
               key_path: "/certs/client.key",
               mode: :verify_full
             ]
    end

    test "turns ssl on from the url's sslmode when the key has it off" do
      assert resolve_url!("sslmode=require", ssl: false)[:ssl] == [mode: :require]
    end

    test "turns ssl off on the url's sslmode=disable whatever the key says" do
      ssl = [ca_cert_path: "/certs/ca.pem", mode: :verify_full]

      assert resolve_url!("sslmode=disable", ssl: ssl)[:ssl] == false
    end

    test "resolves its own resolved options with a url's TLS parameters again the same" do
      config = [
        ssl: [ca_cert_path: "/certs/ca.pem"],
        url: "#{@url}?sslmode=verify-full&sslrootcert=system"
      ]

      resolved = resolve!(config, :dev)

      assert resolve!(Keyword.put(resolved, :url, config[:url]), :dev) == resolved
    end

    # The url carries the password, so each message below, matched in full, leaves it out.

    test "raises on the url's sslmode allow or prefer" do
      for mode <- ["allow", "prefer"] do
        assert_url_error(
          "sslmode=#{mode}",
          "url parameter sslmode=#{mode} in config :hologram, :database isn't supported - Postgrex can't fall back between an encrypted and a plain connection, use sslmode=require or sslmode=disable"
        )
      end
    end

    test "raises on an unknown sslmode in the url" do
      assert_url_error(
        "sslmode=verify_full",
        ~s'invalid url parameter sslmode in config :hologram, :database - expected disable, require, verify-ca or verify-full, got: "verify_full"'
      )
    end

    test "raises on the url's channel_binding=require" do
      assert_url_error(
        "sslmode=require&channel_binding=require",
        "url parameter channel_binding=require in config :hologram, :database isn't supported - Postgrex can't bind the channel, remove the parameter"
      )
    end

    test "raises on an unknown channel_binding in the url" do
      assert_url_error(
        "channel_binding=on",
        ~s'invalid url parameter channel_binding in config :hologram, :database - expected disable or prefer, got: "on"'
      )
    end

    test "raises on an empty certificate parameter in the url" do
      for param <- ["sslrootcert", "sslcert", "sslkey"] do
        assert_url_error(
          "sslmode=verify-full&#{param}=",
          "invalid url parameter #{param} in config :hologram, :database - expected a file path, got an empty value"
        )
      end
    end

    test "raises on the url's ssl parameter" do
      assert_url_error(
        "ssl=true",
        "url parameter ssl in config :hologram, :database isn't supported - use sslmode=verify-full, or ssl: in config :hologram, :database"
      )
    end

    test "raises on the url's pool_size parameter" do
      assert_url_error(
        "pool_size=5",
        "url parameter pool_size in config :hologram, :database isn't supported - set pool_size: next to url: in config :hologram, :database"
      )
    end

    test "raises on an unknown url parameter without its value" do
      assert_url_error(
        "sslmode=require&sslpassword=secret",
        ~s'unknown url parameter "sslpassword" in config :hologram, :database - supported: channel_binding, sslcert, sslkey, sslmode, sslrootcert'
      )
    end

    test "raises on a repeated url parameter" do
      assert_url_error(
        "sslmode=require&sslmode=verify-full",
        "url parameter sslmode in config :hologram, :database is given more than once"
      )
    end

    test "raises on a certificate parameter in the url while ssl is off" do
      for param <- ["sslrootcert", "sslcert", "sslkey"] do
        assert_url_error(
          "#{param}=/certs/file.pem",
          "url parameter #{param} in config :hologram, :database would be ignored - ssl is off - set sslmode in the url, or ssl: in config :hologram, :database"
        )
      end
    end

    test "raises on a certificate parameter in the url under sslmode=disable" do
      assert_url_error(
        "sslmode=disable&sslrootcert=/certs/ca.pem",
        [ssl: [mode: :verify_full]],
        "url parameter sslrootcert in config :hologram, :database would be ignored - sslmode=disable turns ssl off"
      )
    end

    test "raises on the url's sslrootcert under the url's sslmode=require" do
      assert_url_error(
        "sslmode=require&sslrootcert=/certs/ca.pem",
        "url parameter sslrootcert in config :hologram, :database needs sslmode=verify-ca or sslmode=verify-full - sslmode=require doesn't check the server's certificate"
      )
    end

    test "raises on the url's sslrootcert under the key's mode :require" do
      assert_url_error(
        "sslrootcert=/certs/ca.pem",
        [ssl: [mode: :require]],
        "url parameter sslrootcert in config :hologram, :database needs mode :verify_ca or :verify_full - mode :require doesn't check the server's certificate"
      )
    end

    test "raises on the key's ca_cert_path under the url's sslmode=require" do
      assert_url_error(
        "sslmode=require",
        [ssl: [ca_cert_path: "/certs/ca.pem"]],
        "ssl entry :ca_cert_path in config :hologram, :database needs sslmode=verify-ca or sslmode=verify-full - sslmode=require doesn't check the server's certificate"
      )
    end

    test "raises on the url's sslrootcert=system under a mode other than verify_full" do
      assert_url_error(
        "sslmode=verify-ca&sslrootcert=system",
        "url parameter sslrootcert=system in config :hologram, :database needs sslmode=verify-full - sslmode=verify-ca doesn't check the server's host name"
      )

      assert_url_error(
        "sslrootcert=system",
        [ssl: [mode: :verify_ca]],
        "url parameter sslrootcert=system in config :hologram, :database needs mode :verify_full - mode :verify_ca doesn't check the server's host name"
      )

      assert_url_error(
        "sslrootcert=system",
        [ssl: [mode: :require]],
        "url parameter sslrootcert=system in config :hologram, :database needs mode :verify_full - mode :require doesn't check the server's certificate"
      )
    end

    test "raises on a malformed percent-encoding in the url's query" do
      assert_url_error(
        "sslmode=verify-ca&sslrootcert=/certs/ca%zz.pem",
        ~s'invalid url parameter "sslrootcert" in config :hologram, :database - malformed percent-encoding'
      )
    end

    test "raises on an encoded zero byte in the url's query" do
      assert_url_error(
        "sslmode=verify-ca&sslrootcert=/certs/ca%00.pem",
        ~s'invalid url parameter "sslrootcert" in config :hologram, :database - malformed percent-encoding'
      )
    end

    test "raises on the url's sslcert without a key" do
      assert_url_error(
        "sslmode=require&sslcert=/certs/client.pem",
        "url parameter sslcert in config :hologram, :database needs sslkey, the key of the client certificate"
      )
    end

    test "raises on the url's sslkey without a certificate" do
      assert_url_error(
        "sslmode=require&sslkey=/certs/client.key",
        "url parameter sslkey in config :hologram, :database needs sslcert, the client certificate of the key"
      )
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

    # The system's CAs would vouch for any host a public CA issued a certificate to, and mode
    # :verify_ca doesn't check the host name.
    test "raises on the verify_ca mode without a CA" do
      expected_msg =
        "mode :verify_ca in config :hologram, :database needs ssl entry :ca_cert_path or url parameter sslrootcert, the file of the CA to trust - without a host name check, trusting the system's CAs takes mode :verify_full"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([ssl: [mode: :verify_ca]], :dev)
      end
    end

    test "raises on the url's sslmode=verify-ca without a CA" do
      assert_url_error(
        "sslmode=verify-ca",
        "sslmode=verify-ca in config :hologram, :database needs url parameter sslrootcert or ssl entry :ca_cert_path, the file of the CA to trust - without a host name check, trusting the system's CAs takes sslmode=verify-full"
      )
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

    # In a VM of its own, since the ssl application caches the system's CAs for the whole VM, so
    # failing their load here would fail it for the tests running alongside.
    test "raises when a checking mode has no CA and the system's CAs fail to load" do
      {:ok, peer, _node} =
        :peer.start_link(%{
          args: Enum.flat_map(:code.get_path(), &[~c"-pa", &1]),
          connection: :standard_io
        })

      missing_path = Path.join(System.tmp_dir!(), "hologram_no_such_cacerts.pem")

      :ok = :peer.call(peer, :application, :load, [:public_key])
      :ok = :peer.call(peer, :application, :set_env, [:public_key, :cacerts_path, missing_path])

      # Every identity key given under :prod, which has no defaults, since the dev defaults
      # read the otp_app from Mix, which the peer doesn't run.
      resolve_ssl = fn ssl ->
        config = [database: "my_db", host: "db.example.com", password: "p", ssl: ssl, user: "u"]
        :peer.call(peer, Hologram.DB.Config, :resolve!, [config, :prod])[:ssl]
      end

      expected_msg =
        "ssl in config :hologram, :database checks the server's certificate against the system's CAs, which failed to load (:enoent) - set ssl entry :ca_cert_path to the CA to trust"

      assert_error ArgumentError, expected_msg, fn -> resolve_ssl.(true) end

      assert resolve_ssl.(ca_cert_path: "/certs/ca.pem") == [
               ca_cert_path: "/certs/ca.pem",
               mode: :verify_full
             ]

      assert resolve_ssl.(mode: :require) == [mode: :require]
      assert resolve_ssl.(false) == false

      :peer.stop(peer)
    end

    test "raises when identity keys are missing and the environment has no defaults" do
      expected_msg =
        "missing database configuration for :prod - set config :hologram, :database with discrete keys or url:, missing: database, password, user"

      assert_error ArgumentError, expected_msg, fn ->
        resolve!([host: "db.example.com"], :prod)
      end
    end
  end

  defp assert_url_error(query, config \\ [], expected_msg) do
    assert_error ArgumentError, expected_msg, fn -> resolve_url!(query, config) end
  end

  defp resolve_url!(query, config \\ []) do
    resolve!(Keyword.put(config, :url, "#{@url}?#{query}"), :dev)
  end
end
