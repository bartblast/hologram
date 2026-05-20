defmodule Hologram.Realtime.SSE do
  @moduledoc false

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Runtime.Session

  @heartbeat_interval_ms 15_000
  @receipts_refresh_interval_ms 12 * 60 * 60 * 1000

  @doc """
  Builds the SSE event-stream chunk for an `action` broadcast: the standard
  `event:`/`id:`/`data:` framing with the given id and the encoded `%Action{}`
  struct as the data payload.
  """
  @spec encode_action_envelope(integer, Action.t()) :: String.t()
  def encode_action_envelope(id, %Action{} = action) do
    {:ok, data} = Encoder.encode_term(action)
    "event: action\nid: #{id}\ndata: #{data}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk for a `refresh_sub_receipts` event: the
  standard `event:`/`id:`/`data:` framing with the given id and the encoded
  list of `{channel, cid, token}` triples as the data payload.
  """
  @spec encode_refresh_sub_receipts_envelope(integer, [{any, String.t(), String.t()}]) ::
          String.t()
  def encode_refresh_sub_receipts_envelope(id, receipts) do
    {:ok, data} = Encoder.encode_term(receipts)
    "event: refresh_sub_receipts\nid: #{id}\ndata: #{data}\n\n"
  end

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
  @spec process_message(Plug.Conn.t(), term | nil, term | nil, keyword) ::
          {:cont, Plug.Conn.t()}
          | {:cont, Plug.Conn.t(), term | nil, term | nil}
          | {:halt, Plug.Conn.t()}
  def process_message(conn, _session_id, _user_id, opts \\ []) do
    heartbeat_interval_ms =
      Keyword.get(opts, :heartbeat_interval_ms, @heartbeat_interval_ms)

    receipts_refresh_interval_ms =
      Keyword.get(opts, :receipts_refresh_interval_ms, @receipts_refresh_interval_ms)

    receive do
      {:broadcast_action, %Action{} = action, excluded_identities} ->
        if has_excluded_identity?(conn, excluded_identities) do
          {:cont, conn}
        else
          dispatch_broadcast(conn, action)
        end

      {:close, _reason} ->
        {:halt, conn}

      :heartbeat ->
        case Plug.Conn.chunk(conn, ":\n\n") do
          {:ok, conn} ->
            schedule_heartbeat(heartbeat_interval_ms)
            {:cont, conn}

          {:error, _reason} ->
            {:halt, conn}
        end

      {:identity_changed, new_session_id, new_user_id} ->
        {:cont, conn, new_session_id, new_user_id}

      :refresh_receipts ->
        case dispatch_receipts_refresh(conn) do
          {:cont, conn} ->
            schedule_receipts_refresh(receipts_refresh_interval_ms)
            {:cont, conn}

          {:halt, conn} ->
            {:halt, conn}
        end

      {:sub, channel} ->
        Phoenix.PubSub.subscribe(Hologram.PubSub, channel_topic(channel))
        {:cont, conn}

      {:unsub, channel} ->
        Phoenix.PubSub.unsubscribe(Hologram.PubSub, channel_topic(channel))
        {:cont, conn}

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

        receipts_refresh_interval_ms =
          Keyword.get(opts, :receipts_refresh_interval_ms, @receipts_refresh_interval_ms)

        schedule_heartbeat(heartbeat_interval_ms)
        schedule_receipts_refresh(receipts_refresh_interval_ms)

        message_pump_opts = [
          heartbeat_interval_ms: heartbeat_interval_ms,
          receipts_refresh_interval_ms: receipts_refresh_interval_ms
        ]

        {_instance_id, session_id, user_id} = claimed

        conn
        |> attach_validated_subscriptions(validated_bindings)
        |> subscribe_to_identity_channels()
        |> prepare()
        |> message_pump(session_id, user_id, message_pump_opts)

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

  # Public so tests can exercise the pure refresh-list build without entering
  # the blocking message-pump loop.
  @doc false
  @spec build_refresh_receipts(String.t(), %{{any, String.t()} => term | nil}) ::
          [{any, String.t(), String.t()}]
  def build_refresh_receipts(instance_id, bindings) do
    Enum.map(bindings, fn {{channel, cid}, authorizing_user_id} ->
      token = Receipt.issue(channel, cid, instance_id, authorizing_user_id)
      {channel, cid, token}
    end)
  end

  # Public so tests can exercise the identity-topic diff without entering the
  # blocking message-pump loop.
  @doc false
  @spec maybe_reconcile_identity_subs(:session | :user, term | nil, term | nil) :: :ok
  def maybe_reconcile_identity_subs(kind, old, new) when kind in [:session, :user] and old == new,
    do: :ok

  def maybe_reconcile_identity_subs(kind, nil, new) when kind in [:session, :user] do
    new_topic = Realtime.identity_topic(kind, new)
    Phoenix.PubSub.subscribe(Hologram.PubSub, new_topic)
  end

  def maybe_reconcile_identity_subs(kind, old, nil) when kind in [:session, :user] do
    old_topic = Realtime.identity_topic(kind, old)
    Phoenix.PubSub.unsubscribe(Hologram.PubSub, old_topic)
  end

  def maybe_reconcile_identity_subs(kind, old, new) when kind in [:session, :user] do
    old_topic = Realtime.identity_topic(kind, old)
    new_topic = Realtime.identity_topic(kind, new)

    Phoenix.PubSub.unsubscribe(Hologram.PubSub, old_topic)
    Phoenix.PubSub.subscribe(Hologram.PubSub, new_topic)
  end

  # Public so tests can exercise subscription wiring without entering the
  # blocking message-pump loop.
  @doc false
  @spec subscribe_to_identity_channels(Plug.Conn.t()) :: Plug.Conn.t()
  def subscribe_to_identity_channels(initial_conn) do
    conn = Plug.Conn.fetch_query_params(initial_conn)

    instance_id = conn.query_params["instance_id"]
    instance_topic = Realtime.identity_topic(:instance, instance_id)
    Phoenix.PubSub.subscribe(Hologram.PubSub, instance_topic)

    session_id = Session.get_session_id(conn)
    session_topic = Realtime.identity_topic(:session, session_id)
    Phoenix.PubSub.subscribe(Hologram.PubSub, session_topic)

    if user_id = Session.get_user_id(conn) do
      user_topic = Realtime.identity_topic(:user, user_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, user_topic)
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

    case Plug.Conn.chunk(conn, encode_action_envelope(id, action)) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end

  defp dispatch_receipts_refresh(initial_conn) do
    conn = Plug.Conn.fetch_query_params(initial_conn)
    instance_id = conn.query_params["instance_id"]
    bindings = SubscriptionRegistry.bindings_of(instance_id) || %{}

    if map_size(bindings) == 0 do
      {:cont, conn}
    else
      receipts = build_refresh_receipts(instance_id, bindings)
      id = System.unique_integer([:positive, :monotonic])

      case Plug.Conn.chunk(conn, encode_refresh_sub_receipts_envelope(id, receipts)) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end
  end

  defp has_excluded_identity?(conn, excluded_identities) do
    conn
    |> own_identities()
    |> Enum.any?(&(&1 in excluded_identities))
  end

  defp message_pump(conn, session_id, user_id, opts) do
    case process_message(conn, session_id, user_id, opts) do
      {:cont, conn} ->
        message_pump(conn, session_id, user_id, opts)

      {:cont, conn, new_session_id, new_user_id} ->
        message_pump(conn, new_session_id, new_user_id, opts)

      {:halt, conn} ->
        conn
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

  # sobelow_skip ["XSS.SendResp"]
  defp reject_4xx(conn, message) do
    conn
    |> Plug.Conn.send_resp(400, message)
    |> Plug.Conn.halt()
  end

  defp schedule_heartbeat(heartbeat_interval_ms) do
    Process.send_after(self(), :heartbeat, heartbeat_interval_ms)
  end

  defp schedule_receipts_refresh(interval_ms) do
    Process.send_after(self(), :refresh_receipts, interval_ms)
  end
end
