defmodule Hologram.DB.SimpleConnectionTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog

  alias Hologram.DB.Config
  alias Hologram.DB.SimpleConnection
  alias Hologram.Test.ClosingTCP
  alias Hologram.Test.CountingListener
  alias Hologram.Test.DatabaseBootstrap.Connection

  # TODO(#1696): this file goes with Hologram.DB.SimpleConnection. Its callers' own tests of a
  # connect whose socket fails as it opens stay, and then test Postgrex.SimpleConnection.

  defp closing_opts(listener, step) do
    Config.connection_opts(
      port: CountingListener.port(listener),
      socket_options: ClosingTCP.socket_options(step)
    )
  end

  defp start_listener, do: start_supervised!(CountingListener)

  describe "start_link/3" do
    # Linked to the test, so a connection that crashed takes the test with it rather than being
    # started again by a supervisor, which would try again too.
    test "keeps trying a connect whose socket fails as it opens, when told to keep trying" do
      listener = start_listener()

      log =
        capture_log(fn ->
          opts =
            listener
            |> closing_opts(:handshake)
            |> Keyword.merge(auto_reconnect: true, reconnect_backoff: 50, sync_connect: false)

          {:ok, connection} = SimpleConnection.start_link(Connection, nil, opts)

          wait_until(fn -> CountingListener.accepted(listener) >= 3 end)

          assert Process.alive?(connection)

          :gen_statem.stop(connection)
        end)

      assert log =~ "(Hologram.Test.DatabaseBootstrap.Connection) failed to connect to Postgres"
      assert log =~ "tcp peername: invalid argument - :einval"
    end

    test "returns the connection error of a connect at start whose socket fails as it opens" do
      Process.flag(:trap_exit, true)
      opts = closing_opts(start_listener(), :setopts)

      log =
        capture_log(fn ->
          assert {:error, %DBConnection.ConnectionError{message: message}} =
                   SimpleConnection.start_link(Connection, nil, opts)

          assert message == "tcp setopts: invalid argument - :einval"
        end)

      assert log =~ "failed to connect to Postgres"

      refute_received {:EXIT, _pid, _reason}
    end

    test "keeps trying a connect at start whose socket fails as it opens, when told to keep trying" do
      listener = start_listener()

      log =
        capture_log(fn ->
          opts =
            listener
            |> closing_opts(:setopts)
            |> Keyword.merge(auto_reconnect: true, reconnect_backoff: 50, sync_connect: true)

          assert {:ok, connection} = SimpleConnection.start_link(Connection, nil, opts)

          wait_until(fn -> CountingListener.accepted(listener) >= 3 end)

          assert Process.alive?(connection)

          :gen_statem.stop(connection)
        end)

      assert log =~ "tcp setopts: invalid argument - :einval"
    end

    @tag :database
    test "connects at start and answers" do
      {:ok, connection} =
        SimpleConnection.start_link(Connection, nil, Config.connection_opts(database: "postgres"))

      assert %Postgrex.Result{rows: [["1"]]} = Connection.query!(connection, "SELECT 1")

      :gen_statem.stop(connection)
    end

    @tag :database
    test "connects after start and answers" do
      opts = Config.connection_opts(database: "postgres", sync_connect: false)

      {:ok, connection} = SimpleConnection.start_link(Connection, nil, opts)

      assert %Postgrex.Result{rows: [["1"]]} = Connection.query!(connection, "SELECT 1")

      :gen_statem.stop(connection)
    end

    test "registers the connection under the given name" do
      name = __MODULE__.Named

      opts =
        start_listener()
        |> closing_opts(:setopts)
        |> Keyword.merge(auto_reconnect: true, name: name, sync_connect: false)

      capture_log(fn ->
        {:ok, connection} = SimpleConnection.start_link(Connection, nil, opts)

        assert Process.whereis(name) == connection

        :gen_statem.stop(connection)
      end)
    end
  end
end
