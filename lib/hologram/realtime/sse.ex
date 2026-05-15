defmodule Hologram.Realtime.SSE do
  @moduledoc false

  alias Hologram.Runtime.Session

  @default_heartbeat_interval_ms 15_000

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

  # Public so tests can step the pump one message at a time without spawning
  # the blocking loop.
  @doc false
  @spec process_message(Plug.Conn.t(), non_neg_integer) ::
          {:cont, Plug.Conn.t()} | {:halt, Plug.Conn.t()}
  def process_message(conn, heartbeat_interval_ms) do
    # TODO: typed message clauses (PubSub broadcasts, sub/unsub,
    # identity-change) land in future phases.
    receive do
      :heartbeat ->
        case Plug.Conn.chunk(conn, ":\n\n") do
          {:ok, conn} ->
            schedule_heartbeat(heartbeat_interval_ms)
            {:cont, conn}

          {:error, _reason} ->
            {:halt, conn}
        end

      {:close, _reason} ->
        {:halt, conn}

      _msg ->
        {:cont, conn}
    end
  end

  @doc """
  Opens an SSE stream on the given conn and enters a message-pump loop that
  runs until the connection is closed.

  ## Options

    * `:heartbeat_interval_ms` - milliseconds between proxy-keep-alive comment
      writes. Defaults to `15_000`.
  """
  @spec stream(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def stream(conn, opts \\ []) do
    heartbeat_interval_ms =
      Keyword.get(opts, :heartbeat_interval_ms, @default_heartbeat_interval_ms)

    schedule_heartbeat(heartbeat_interval_ms)

    conn
    |> subscribe_to_identity_channels()
    |> prepare()
    |> message_pump(heartbeat_interval_ms)
  end

  defp message_pump(conn, heartbeat_interval_ms) do
    case process_message(conn, heartbeat_interval_ms) do
      {:cont, conn} -> message_pump(conn, heartbeat_interval_ms)
      {:halt, conn} -> conn
    end
  end

  defp schedule_heartbeat(heartbeat_interval_ms) do
    Process.send_after(self(), :heartbeat, heartbeat_interval_ms)
  end

  # Public so tests can exercise subscription wiring without entering the
  # blocking message-pump loop.
  @doc false
  @spec subscribe_to_identity_channels(Plug.Conn.t()) :: Plug.Conn.t()
  def subscribe_to_identity_channels(initial_conn) do
    conn = Plug.Conn.fetch_query_params(initial_conn)
    instance_id = conn.query_params["instance_id"]
    instance_topic = "hologram:channel:instance:#{instance_id}"

    Phoenix.PubSub.subscribe(Hologram.PubSub, instance_topic)

    case Session.fetch_id(conn) do
      {:ok, session_id} ->
        session_topic = "hologram:channel:session:#{session_id}"
        Phoenix.PubSub.subscribe(Hologram.PubSub, session_topic)

      :error ->
        :ok
    end

    conn
  end
end
