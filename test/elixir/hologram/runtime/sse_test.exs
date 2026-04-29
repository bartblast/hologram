defmodule Hologram.Runtime.SSETest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Runtime.SSE

  # Used by tests that send :hologram_sse_close immediately and want the
  # heartbeat timer to never fire, so the conn captures exactly the one
  # initial heartbeat written before the loop enters its receive block.
  @opts [heartbeat_interval_ms: 1_000]

  defp run_stream(opts) do
    Task.async(fn ->
      :get
      |> Plug.Test.conn("/hologram/sse")
      |> SSE.stream(opts)
    end)
  end

  describe "stream/2" do
    test "sets SSE response headers" do
      task = run_stream(@opts)
      send(task.pid, :hologram_sse_close)
      conn = Task.await(task)

      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-cache"]
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/event-stream"]
      assert Plug.Conn.get_resp_header(conn, "x-accel-buffering") == ["no"]
    end

    test "starts a chunked 200 response" do
      task = run_stream(@opts)
      send(task.pid, :hologram_sse_close)
      conn = Task.await(task)

      assert conn.state == :chunked
      assert conn.status == 200
    end

    test "writes the heartbeat in SSE comment-line format" do
      task = run_stream(@opts)
      send(task.pid, :hologram_sse_close)
      conn = Task.await(task)

      assert conn.resp_body == ": hb\n\n"
    end

    test "writes a comment-line heartbeat chunk on each tick" do
      task = run_stream(heartbeat_interval_ms: 5)
      Process.sleep(20)
      send(task.pid, :hologram_sse_close)
      conn = Task.await(task)

      heartbeat_count =
        conn.resp_body
        |> String.split(": hb\n\n")
        |> length()
        |> Kernel.-(1)

      assert heartbeat_count >= 2
    end

    test "exits cleanly when :hologram_sse_close arrives mid-loop after several ticks" do
      task = run_stream(heartbeat_interval_ms: 5)
      Process.sleep(20)
      send(task.pid, :hologram_sse_close)

      # Tight Task.await timeout: if the loop ignored :hologram_sse_close
      # and kept ticking, await would crash before the loop ever exited.
      conn = Task.await(task, 100)

      assert conn.state == :chunked
    end
  end
end
