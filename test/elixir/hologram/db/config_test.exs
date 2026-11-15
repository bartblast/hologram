defmodule Hologram.DB.ConfigTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Config

  describe "connection_opts/1" do
    test "returns the configured database as Postgrex options" do
      opts = connection_opts()

      assert opts[:database] == "hologram_test"
      assert opts[:hostname] == "localhost"
      assert opts[:password] == "postgres"
      assert opts[:port] == 5432
      assert opts[:username] == "postgres"
    end

    test "applies the given overrides" do
      assert connection_opts(database: "other")[:database] == "other"
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

  describe "resolve!/2" do
    test "applies dev defaults when no config is given" do
      assert resolve!([], :dev) == [
               database: "hologram_dev",
               host: "localhost",
               password: "postgres",
               pool_size: 10,
               port: 5432,
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
               user: "alice"
             ]
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
