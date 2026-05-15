defmodule Hologram.Realtime.SSETest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Realtime.SSE

  # Plug.Test.Adapter sends `{:plug_conn, :sent}` to the owner on send_chunked.
  # Consume it so tests that drive process_message/2 directly see only the
  # messages they sent themselves.
  defp flush_plug_conn_sent do
    receive do
      {:plug_conn, :sent} -> :ok
    end
  end

  defp prepared_test_conn do
    conn = Plug.Test.conn(:get, "/") |> SSE.prepare()
    flush_plug_conn_sent()
    conn
  end

  describe "prepare/1" do
    test "sets SSE response headers" do
      conn = Plug.Test.conn(:get, "/")
      result = SSE.prepare(conn)

      assert result.resp_headers == [
               {"cache-control", "no-cache"},
               {"connection", "keep-alive"},
               {"content-type", "text/event-stream"}
             ]
    end

    test "opens a chunked response with status 200" do
      conn = Plug.Test.conn(:get, "/")
      result = SSE.prepare(conn)

      assert result.state == :chunked
      assert result.status == 200
    end
  end

  describe "process_message/2" do
    test "writes an SSE comment line on :heartbeat" do
      conn = prepared_test_conn()
      send(self(), :heartbeat)

      {:cont, conn} = SSE.process_message(conn, 30_000)

      assert conn.resp_body == ":\n\n"
    end

    test "schedules the next heartbeat after handling :heartbeat" do
      conn = prepared_test_conn()
      send(self(), :heartbeat)

      SSE.process_message(conn, 30)

      assert_receive :heartbeat, 100
    end

    test "continues without writing on unknown messages" do
      conn = prepared_test_conn()
      send(self(), :some_unknown_message)

      {:cont, conn} = SSE.process_message(conn, 30_000)

      assert conn.resp_body == ""
    end

    test "halts on {:close, reason}" do
      conn = prepared_test_conn()
      send(self(), {:close, :superseded})

      assert {:halt, ^conn} = SSE.process_message(conn, 30_000)
    end
  end

  describe "stream/2" do
    test "blocks on receive after preparing the stream" do
      conn = Plug.Test.conn(:get, "/")
      pid = spawn(fn -> SSE.stream(conn) end)

      Process.sleep(50)

      assert Process.alive?(pid)

      Process.exit(pid, :kill)
    end

    test "ignores unknown messages without exiting" do
      conn = Plug.Test.conn(:get, "/")
      pid = spawn(fn -> SSE.stream(conn) end)

      Process.sleep(50)
      send(pid, :some_unknown_message)
      send(pid, {:another, "message"})
      Process.sleep(50)

      assert Process.alive?(pid)

      Process.exit(pid, :kill)
    end

    test "exits cleanly on {:close, reason}" do
      conn = Plug.Test.conn(:get, "/")
      pid = spawn(fn -> SSE.stream(conn) end)

      Process.sleep(50)
      send(pid, {:close, :superseded})
      Process.sleep(50)

      refute Process.alive?(pid)
    end
  end
end
