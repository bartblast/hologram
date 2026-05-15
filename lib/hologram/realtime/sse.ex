defmodule Hologram.Realtime.SSE do
  @moduledoc false

  # Public so tests can exercise the prep step without entering the blocking
  # message-pump loop.
  @doc false
  @spec prepare(Plug.Conn.t()) :: Plug.Conn.t()
  def prepare(conn) do
    # TODO: When Bandit ships a per-connection read_timeout setter (see
    # bandit_sse_timeout_note.md / upstream issue), call it here so individual
    # SSE connections survive past Bandit's 60s read_timeout. Until then, the
    # 60s reap is absorbed by the JS-driven reconnect path.
    conn
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.put_resp_header("connection", "keep-alive")
    |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
    |> Plug.Conn.send_chunked(200)
  end

  @doc """
  Opens an SSE stream on the given conn and enters a message-pump loop that
  runs until the connection is closed.
  """
  @spec stream(Plug.Conn.t()) :: Plug.Conn.t()
  def stream(conn) do
    conn
    |> prepare()
    |> message_pump()
  end

  defp message_pump(conn) do
    # TODO: typed message clauses (heartbeat, close, PubSub broadcasts,
    # sub/unsub, identity-change) land in future phases.
    receive do
      _msg -> message_pump(conn)
    end
  end
end
