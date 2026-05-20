defmodule Hologram.Realtime.SSE do
  @moduledoc false

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Runtime.Session

  @heartbeat_interval_ms 15_000

  @doc """
  Builds the SSE event envelope for a broadcast `%Action{}`.

  The envelope shape is the standard SSE event framing:

      event: action
      id: <id>
      data: <encoded>

  where `<encoded>` is the result of `Hologram.Compiler.Encoder.encode_term/1`
  on the `%Action{}` struct - the same path the controller uses for command
  responses.
  """
  @spec encode_envelope(integer, Action.t()) :: String.t()
  def encode_envelope(id, %Action{} = action) do
    {:ok, data} = Encoder.encode_term(action)
    "event: action\nid: #{id}\ndata: #{data}\n\n"
  end

  @doc """
  Returns the SSE heartbeat interval (milliseconds between proxy-keep-alive
  comment-line writes) when `stream/2` is called without a `:heartbeat_interval_ms`
  override.
  """
  @spec heartbeat_interval_ms() :: pos_integer
  def heartbeat_interval_ms, do: @heartbeat_interval_ms

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
    # TODO: remaining typed message clauses (unsub, identity-change) land in
    # future phases.
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

      {:sub, channel} ->
        Phoenix.PubSub.subscribe(Hologram.PubSub, channel_topic(channel))
        {:cont, conn}

      {:broadcast_action, %Action{} = action, excluded_identities} ->
        if has_excluded_identity?(conn, excluded_identities) do
          {:cont, conn}
        else
          dispatch_broadcast(conn, action)
        end

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
    conn = Plug.Conn.fetch_query_params(conn)
    handshake_id = conn.query_params["handshake_id"]

    server_wait_ms =
      Keyword.get(opts, :server_wait_ms, Handshake.server_wait_ms())

    claimed = claimed_identity(conn)

    case Handshake.redeem(handshake_id, server_wait_ms) do
      {:ok, validated_bindings, ^claimed} ->
        heartbeat_interval_ms =
          Keyword.get(opts, :heartbeat_interval_ms, @heartbeat_interval_ms)

        schedule_heartbeat(heartbeat_interval_ms)

        conn
        |> attach_validated_subscriptions(validated_bindings)
        |> subscribe_to_identity_channels()
        |> prepare()
        |> message_pump(heartbeat_interval_ms)

      :error ->
        reject_4xx(conn, "Handshake redemption failed")

      {:ok, _bindings, _stashed} ->
        reject_4xx(conn, "Handshake identity mismatch")
    end
  end

  # Public so tests can exercise the registry attach + per-channel PubSub
  # subscribes without entering the blocking message-pump loop.
  @doc false
  @spec attach_validated_subscriptions(Plug.Conn.t(), [{{any, String.t()}, term | nil}]) ::
          Plug.Conn.t()
  def attach_validated_subscriptions(initial_conn, validated_bindings) do
    conn = Plug.Conn.fetch_query_params(initial_conn)

    instance_id = conn.query_params["instance_id"]
    session_id = Session.get_session_id(conn)
    user_id = Session.get_user_id(conn)

    validated_channels =
      SubscriptionRegistry.attach_connection(
        instance_id,
        session_id,
        user_id,
        self(),
        validated_bindings
      )

    Enum.each(validated_channels, fn channel ->
      Phoenix.PubSub.subscribe(Hologram.PubSub, channel_topic(channel))
    end)

    conn
  end

  # Public so tests can exercise subscription wiring without entering the
  # blocking message-pump loop.
  @doc false
  @spec subscribe_to_identity_channels(Plug.Conn.t()) :: Plug.Conn.t()
  def subscribe_to_identity_channels(initial_conn) do
    conn = Plug.Conn.fetch_query_params(initial_conn)

    instance_id = conn.query_params["instance_id"]
    Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram:channel:instance:#{instance_id}")

    session_id = Session.get_session_id(conn)
    Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram:channel:session:#{session_id}")

    if user_id = Session.get_user_id(conn) do
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram:channel:user:#{user_id}")
    end

    conn
  end

  defp channel_topic(channel) when is_atom(channel) do
    "hologram:channel:#{channel}"
  end

  defp channel_topic(channel) when is_tuple(channel) do
    parts =
      channel
      |> Tuple.to_list()
      |> Enum.join(":")

    "hologram:channel:#{parts}"
  end

  defp claimed_identity(conn) do
    {
      conn.query_params["instance_id"],
      Session.get_session_id(conn),
      Session.get_user_id(conn)
    }
  end

  defp dispatch_broadcast(conn, action) do
    id = System.unique_integer([:positive, :monotonic])

    case Plug.Conn.chunk(conn, encode_envelope(id, action)) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end

  defp has_excluded_identity?(conn, excluded_identities) do
    conn
    |> own_identities()
    |> Enum.any?(&(&1 in excluded_identities))
  end

  defp message_pump(conn, heartbeat_interval_ms) do
    case process_message(conn, heartbeat_interval_ms) do
      {:cont, conn} -> message_pump(conn, heartbeat_interval_ms)
      {:halt, conn} -> conn
    end
  end

  defp own_identities(conn) do
    conn = Plug.Conn.fetch_query_params(conn)
    instance_id = conn.query_params["instance_id"]
    session_id = Session.get_session_id(conn)

    base = [{:instance, instance_id}, {:session, session_id}]

    case Session.get_user_id(conn) do
      nil -> base
      user_id -> [{:user, user_id} | base]
    end
  end

  defp reject_4xx(conn, message) do
    conn
    |> Plug.Conn.send_resp(400, message)
    |> Plug.Conn.halt()
  end

  defp schedule_heartbeat(heartbeat_interval_ms) do
    Process.send_after(self(), :heartbeat, heartbeat_interval_ms)
  end
end
