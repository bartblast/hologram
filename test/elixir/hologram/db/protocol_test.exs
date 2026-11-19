defmodule Hologram.DB.ProtocolTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog

  alias Hologram.DB.Config
  alias Hologram.DB.Protocol
  alias Hologram.Test.ClosingTCP
  alias Hologram.Test.CountingListener

  # TODO(#1696): this file goes with Hologram.DB.Protocol. Keep the connect/1 tests as tests of
  # Postgrex.Protocol.connect/1, which then returns the error itself.

  defp connect_opts(listener, step) do
    Config.connection_opts(
      port: CountingListener.port(listener),
      socket_options: ClosingTCP.socket_options(step),
      types: Postgrex.DefaultTypes
    )
  end

  defp start_listener, do: start_supervised!(CountingListener)

  defp raise_from(frame, term) do
    :erlang.raise(:error, {:badmatch, term}, [frame])
  end

  describe "connect/1" do
    test "returns a connection error when the socket fails in Postgrex's connect" do
      opts = connect_opts(start_listener(), :setopts)

      assert {:error, %DBConnection.ConnectionError{message: message}} = Protocol.connect(opts)
      assert message == "tcp setopts: invalid argument - :einval"
    end

    test "returns a connection error when the socket fails in Postgrex's handshake" do
      opts = connect_opts(start_listener(), :handshake)

      assert {:error, %DBConnection.ConnectionError{message: message}} = Protocol.connect(opts)
      assert message == "tcp peername: invalid argument - :einval"
    end
  end

  describe "rescue_peer_reset/1" do
    test "returns what the function returns" do
      assert Protocol.rescue_peer_reset(fn -> :result end) == :result
    end

    test "closes the socket the function left open and no other, leaving no exit message behind" do
      Process.flag(:trap_exit, true)
      port = CountingListener.port(start_listener())
      test_pid = self()

      {:ok, socket_before} = :gen_tcp.connect(~c"localhost", port, active: false)

      assert {:error, %DBConnection.ConnectionError{}} =
               Protocol.rescue_peer_reset(fn ->
                 {:ok, socket} = :gen_tcp.connect(~c"localhost", port, active: false)
                 send(test_pid, {:socket, socket})

                 raise_from({Postgrex.Protocol, :handshake, 3, []}, {:error, :einval})
               end)

      assert_received {:socket, socket}
      assert Port.info(socket) == nil
      refute_received {:EXIT, ^socket, _reason}

      assert Port.info(socket_before) != nil
    end

    test "raises again a match error whose term isn't an error with an atom reason" do
      assert_raise MatchError, fn ->
        Protocol.rescue_peer_reset(fn ->
          raise_from({Postgrex.Protocol, :handshake, 3, []}, {:error, "reason"})
        end)
      end
    end

    test "raises again a match error from another step of Postgrex's connect" do
      assert_raise MatchError, fn ->
        Protocol.rescue_peer_reset(fn ->
          raise_from({Postgrex.Protocol, :startup, 2, []}, {:error, :einval})
        end)
      end
    end

    test "raises again a match error raised in the function itself" do
      assert_raise MatchError, fn ->
        Protocol.rescue_peer_reset(fn ->
          {:ok, _value} = Process.get(:no_such_key, {:error, :einval})
        end)
      end
    end
  end

  describe "start_link/1" do
    # The pool's supervisor restarts a connection that crashed, so it tries again either way: the
    # log tells a connect that failed from one that raised.
    test "starts a pool whose connections back off and try again when the socket fails" do
      listener = start_listener()

      log =
        capture_log(fn ->
          {:ok, pool} =
            listener
            |> connect_opts(:setopts)
            |> Keyword.merge(backoff_max: 50, backoff_min: 10, pool_size: 1)
            |> Protocol.start_link()

          wait_until(fn -> CountingListener.accepted(listener) >= 3 end)

          GenServer.stop(pool)
        end)

      assert log =~ "failed to connect"
      assert log =~ "tcp setopts"
      refute log =~ "MatchError"
    end
  end
end
