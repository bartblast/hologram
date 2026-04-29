defmodule Hologram.Runtime.SSE do
  @moduledoc false

  import Plug.Conn

  # 25s sits below the typical proxy/load balancer idle timeout floor
  # (Heroku 30s, ALB/Nginx 60s) so heartbeats prevent silent disconnects.
  @default_heartbeat_interval_ms 25_000

  # SSE comment line: ":" prefix marks the line as a comment (ignored by
  # the browser's EventSource), "\n\n" terminates the SSE event.
  @heartbeat_chunk ": hb\n\n"

  @spec stream(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def stream(conn, opts \\ []) do
    interval =
      Keyword.get(opts, :heartbeat_interval_ms, @default_heartbeat_interval_ms)

    conn
    # Prevents intermediate caches and the browser from holding onto a
    # response that is unique per request and never re-fetchable.
    |> put_resp_header("cache-control", "no-cache")
    # Required MIME type that switches the browser's EventSource into
    # SSE-parsing mode; any other type and events won't be delivered.
    |> put_resp_header("content-type", "text/event-stream")
    # Disables Nginx response buffering so chunks flush immediately
    # instead of accumulating until the buffer fills.
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
    |> heartbeat_loop(interval)
  end

  # receive-with-timeout (rather than Process.sleep) keeps the wait
  # interruptible by control messages and action dispatches.
  defp heartbeat_loop(conn, interval) do
    case chunk(conn, @heartbeat_chunk) do
      {:ok, conn} ->
        receive do
          :hologram_sse_close -> conn
        after
          interval -> heartbeat_loop(conn, interval)
        end

      # Client disconnected. Fire-and-forget contract: no retry.
      {:error, _reason} ->
        conn
    end
  end
end
