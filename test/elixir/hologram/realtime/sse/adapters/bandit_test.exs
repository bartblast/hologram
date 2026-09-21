defmodule Hologram.Realtime.SSE.Adapters.BanditTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Realtime.SSE.Adapters.Bandit

  describe "handle_message/1" do
    test "closes the stream on an HTTP/2 stream reset" do
      assert handle_message({:bandit, {:rst_stream, 8}}) == :closed
    end

    test "closes the stream on a socket close and hands the message back to the socket's owner" do
      assert handle_message({:tcp_closed, :dummy_socket}) == :closed
      assert_received {:tcp_closed, :dummy_socket}
    end

    test "closes the stream on bytes from the socket and hands them back to the socket's owner" do
      assert handle_message({:tcp, :dummy_socket, "stray bytes"}) == :closed
      assert_received {:tcp, :dummy_socket, "stray bytes"}
    end

    test "ignores any other message" do
      assert handle_message(:some_unknown_message) == :ignore
    end
  end

  describe "watch/1" do
    test "arms the socket of an HTTP/1.1 connection, so a client close reaches the mailbox" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(listen_socket)
      {:ok, client_socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      {:ok, server_socket} = :gen_tcp.accept(listen_socket)

      adapter_state = %{
        transport: %{
          __struct__: Bandit.HTTP1.Socket,
          socket: %{socket: server_socket, transport_module: :inet}
        }
      }

      conn = %Plug.Conn{adapter: {Bandit.Adapter, adapter_state}}

      assert watch(conn) == :ok

      :ok = :gen_tcp.close(client_socket)

      assert_receive {:tcp_closed, ^server_socket}, 1_000

      :gen_tcp.close(listen_socket)
    end

    test "arms nothing for any other connection" do
      conn = Plug.Test.conn(:get, "/")

      assert watch(conn) == :ok
    end
  end
end
