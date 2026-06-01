defmodule Hologram.Realtime.SSE do
  @moduledoc false

  require Logger

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Runtime.Session

  @heartbeat_interval_ms 15_000
  @max_heap_size_words 1_000_000
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
  Builds the SSE event-stream chunk for an `add_sub_receipts` event: the
  standard `event:`/`id:`/`data:` framing with the given id and the encoded
  list of `{channel, cid, token}` triples as the data payload.
  """
  @spec encode_add_sub_receipts_envelope(integer, [{any, String.t(), String.t()}]) ::
          String.t()
  def encode_add_sub_receipts_envelope(id, receipts) do
    {:ok, data} = Encoder.encode_term(receipts)
    "event: add_sub_receipts\nid: #{id}\ndata: #{data}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk for a `broadcast` event: the standard
  `event:`/`id:`/`data:` framing with the given id and the encoded
  `{action_name, params, [cid1, cid2, ...]}` tuple as the data payload.

  The cids list lets the client iterate per-cid dispatch from a single
  bundled chunk rather than receiving one `event: action` per matching cid.
  """
  @spec encode_broadcast_envelope(integer, atom, map, [String.t()]) :: String.t()
  def encode_broadcast_envelope(id, action_name, params, cids) do
    {:ok, data} = Encoder.encode_term({action_name, params, cids})
    "event: broadcast\nid: #{id}\ndata: #{data}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk for a `drop_sub_receipts` event: the
  standard `event:`/`id:`/`data:` framing with the given id and the encoded
  list of `{channel, cid}` keys as the data payload.
  """
  @spec encode_drop_sub_receipts_envelope(integer, [{any, String.t()}]) :: String.t()
  def encode_drop_sub_receipts_envelope(id, keys) do
    {:ok, data} = Encoder.encode_term(keys)
    "event: drop_sub_receipts\nid: #{id}\ndata: #{data}\n\n"
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
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def process_message(conn, session_id, user_id, opts \\ []) do
    heartbeat_interval_ms =
      Keyword.get(opts, :heartbeat_interval_ms, @heartbeat_interval_ms)

    receipts_refresh_interval_ms =
      Keyword.get(opts, :receipts_refresh_interval_ms, @receipts_refresh_interval_ms)

    receive do
      {:add_sub_receipts, receipts} ->
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = encode_add_sub_receipts_envelope(id, receipts)

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end

      {:broadcast_action, channel, action_name, params, excluded_identities} ->
        conn = Plug.Conn.fetch_query_params(conn)
        instance_id = conn.query_params["instance_id"]

        if has_excluded_identity?(instance_id, session_id, user_id, excluded_identities) do
          {:cont, conn}
        else
          bindings = SubscriptionRegistry.bindings_of(instance_id) || %{}

          matching_cids =
            for {{ch, cid}, _user_id} <- bindings, ch == channel, do: cid

          dispatch_broadcast_to_cids(conn, action_name, params, matching_cids)
        end

      {:close, _reason} ->
        {:halt, conn}

      {:drop_channel, channel} ->
        conn = Plug.Conn.fetch_query_params(conn)
        instance_id = conn.query_params["instance_id"]
        bindings = SubscriptionRegistry.bindings_of(instance_id) || %{}

        keys =
          bindings
          |> Map.keys()
          |> Enum.filter(fn {ch, _cid} -> ch == channel end)

        drop_keys_and_emit(conn, instance_id, keys)

      {:drop_sub_receipts, keys} ->
        conn = Plug.Conn.fetch_query_params(conn)
        instance_id = conn.query_params["instance_id"]
        drop_keys_and_emit(conn, instance_id, keys)

      :heartbeat ->
        case Plug.Conn.chunk(conn, ":\n\n") do
          {:ok, conn} ->
            schedule_heartbeat(heartbeat_interval_ms)
            {:cont, conn}

          {:error, _reason} ->
            {:halt, conn}
        end

      {:identity_changed, new_session_id, new_user_id} ->
        maybe_reconcile_identity_subs(:session, session_id, new_session_id)
        maybe_reconcile_session_announce_sub(session_id, new_session_id)
        maybe_reconcile_identity_subs(:user, user_id, new_user_id)
        maybe_reconcile_user_announce_sub(user_id, new_user_id)

        conn = Plug.Conn.fetch_query_params(conn)
        instance_id = conn.query_params["instance_id"]
        SubscriptionRegistry.update_identity(instance_id, new_session_id, new_user_id)

        case maybe_drop_identity_change_bindings(conn, instance_id, user_id, new_user_id) do
          {:cont, conn} -> {:cont, conn, new_session_id, new_user_id}
          {:halt, conn} -> {:halt, conn}
        end

      :refresh_receipts ->
        case dispatch_receipts_refresh(conn) do
          {:cont, conn} ->
            schedule_receipts_refresh(receipts_refresh_interval_ms)
            {:cont, conn}

          {:halt, conn} ->
            {:halt, conn}
        end

      {:sub, channel} ->
        topic = Realtime.channel_topic(channel)
        Phoenix.PubSub.subscribe(Hologram.PubSub, topic)
        {:cont, conn}

      {:unsub, channel} ->
        topic = Realtime.channel_topic(channel)
        Phoenix.PubSub.unsubscribe(Hologram.PubSub, topic)
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
        configure_backpressure_safety_net()

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
        |> subscribe_to_announce_topics()
        |> prepare()
        |> stream_until_closed(session_id, user_id, message_pump_opts)

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
      topic = Realtime.channel_topic(channel)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)
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

  # Public so tests can exercise the announce-topic swap without entering the
  # blocking message-pump loop.
  @doc false
  @spec maybe_reconcile_session_announce_sub(term | nil, term | nil) :: :ok
  def maybe_reconcile_session_announce_sub(old, new) when old == new, do: :ok

  def maybe_reconcile_session_announce_sub(nil, new) do
    new_topic = Realtime.session_announce_topic(new)
    Phoenix.PubSub.subscribe(Hologram.PubSub, new_topic)
  end

  def maybe_reconcile_session_announce_sub(old, nil) do
    old_topic = Realtime.session_announce_topic(old)
    Phoenix.PubSub.unsubscribe(Hologram.PubSub, old_topic)
  end

  def maybe_reconcile_session_announce_sub(old, new) do
    old_topic = Realtime.session_announce_topic(old)
    new_topic = Realtime.session_announce_topic(new)

    Phoenix.PubSub.unsubscribe(Hologram.PubSub, old_topic)
    Phoenix.PubSub.subscribe(Hologram.PubSub, new_topic)
  end

  # Public so tests can exercise the announce-topic swap without entering the
  # blocking message-pump loop.
  @doc false
  @spec maybe_reconcile_user_announce_sub(term | nil, term | nil) :: :ok
  def maybe_reconcile_user_announce_sub(old, new) when old == new, do: :ok

  def maybe_reconcile_user_announce_sub(nil, new) do
    new_topic = Realtime.user_announce_topic(new)
    Phoenix.PubSub.subscribe(Hologram.PubSub, new_topic)
  end

  def maybe_reconcile_user_announce_sub(old, nil) do
    old_topic = Realtime.user_announce_topic(old)
    Phoenix.PubSub.unsubscribe(Hologram.PubSub, old_topic)
  end

  def maybe_reconcile_user_announce_sub(old, new) do
    old_topic = Realtime.user_announce_topic(old)
    new_topic = Realtime.user_announce_topic(new)

    Phoenix.PubSub.unsubscribe(Hologram.PubSub, old_topic)
    Phoenix.PubSub.subscribe(Hologram.PubSub, new_topic)
  end

  # Public so tests can exercise subscription wiring without entering the
  # blocking message-pump loop.
  @doc false
  @spec subscribe_to_announce_topics(Plug.Conn.t()) :: Plug.Conn.t()
  def subscribe_to_announce_topics(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    instance_id = conn.query_params["instance_id"]
    instance_topic = Realtime.instance_announce_topic(instance_id)
    Phoenix.PubSub.subscribe(Hologram.PubSub, instance_topic)

    session_id = Session.get_session_id(conn)
    session_topic = Realtime.session_announce_topic(session_id)
    Phoenix.PubSub.subscribe(Hologram.PubSub, session_topic)

    if user_id = Session.get_user_id(conn) do
      user_topic = Realtime.user_announce_topic(user_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, user_topic)
    end

    conn
  end

  defp claimed_identity(conn) do
    {
      conn.query_params["instance_id"],
      Session.get_session_id(conn),
      Session.get_user_id(conn)
    }
  end

  # Caps the SSE process's heap so a slow consumer can't bloat the BEAM by
  # accumulating broadcasts in its mailbox. Depends on the default `:on_heap`
  # mailbox - do NOT switch the SSE process to `message_queue_data: :off_heap`
  # without revisiting this guard, since off-heap message data is not counted
  # against `:max_heap_size`.
  defp configure_backpressure_safety_net do
    Process.flag(:max_heap_size, %{
      size: @max_heap_size_words,
      kill: true,
      error_logger: true
    })
  end

  defp dispatch_broadcast_to_cids(conn, _action_name, _params, []), do: {:cont, conn}

  defp dispatch_broadcast_to_cids(conn, action_name, params, cids) do
    id = System.unique_integer([:positive, :monotonic])
    chunk = encode_broadcast_envelope(id, action_name, params, cids)

    case Plug.Conn.chunk(conn, chunk) do
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

  defp drop_keys_and_emit(conn, _instance_id, []), do: {:cont, conn}

  defp drop_keys_and_emit(conn, instance_id, keys) do
    {_actually_dropped, zero_crossing_channels} =
      SubscriptionRegistry.drop_keys(instance_id, keys)

    Enum.each(zero_crossing_channels, fn channel ->
      topic = Realtime.channel_topic(channel)
      Phoenix.PubSub.unsubscribe(Hologram.PubSub, topic)
    end)

    id = System.unique_integer([:positive, :monotonic])
    chunk_data = encode_drop_sub_receipts_envelope(id, keys)

    case Plug.Conn.chunk(conn, chunk_data) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end

  defp has_excluded_identity?(instance_id, session_id, user_id, excluded_identities) do
    instance_id
    |> own_identities(session_id, user_id)
    |> Enum.any?(&(&1 in excluded_identities))
  end

  defp maybe_drop_identity_change_bindings(conn, _instance_id, user_id, user_id),
    do: {:cont, conn}

  defp maybe_drop_identity_change_bindings(conn, instance_id, _old_user_id, new_user_id) do
    {dropped_keys, zero_crossing_channels} =
      SubscriptionRegistry.drop_for_identity_change(instance_id, new_user_id)

    Enum.each(zero_crossing_channels, fn channel ->
      topic = Realtime.channel_topic(channel)
      Phoenix.PubSub.unsubscribe(Hologram.PubSub, topic)
    end)

    case dropped_keys do
      [] ->
        {:cont, conn}

      _keys ->
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = encode_drop_sub_receipts_envelope(id, dropped_keys)

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end
    end
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

  defp own_identities(instance_id, session_id, user_id) do
    base = [{:instance, instance_id}, {:session, session_id}]

    case user_id do
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

  # Runs the message pump until the stream closes. A write to a transport the
  # client has already dropped is returned as {:error, _reason} by some servers
  # and surfaces as a raised exception or an exit by others, such as Bandit. The
  # pump only guards the returned tuple, so without this catch the non-tuple
  # variants escape a committed chunked response into the endpoint's RenderErrors.
  # RenderErrors wraps the plug in a catch for every kind - error, exit and throw
  # alike - so any of them reaches put_view, which cannot render an already-sent
  # conn and re-raises as Plug.Conn.AlreadySentError, masking the original cause.
  # Catching every kind here closes the stream the same way the {:error, _reason}
  # branch does, before it can escape. A plain rescue would miss the exit variant.
  #
  # TODO: The :error log below is temporary. I believe every cause that reaches
  # this catch is a benign client disconnect (the non-tuple counterpart of the
  # {:error, :closed} return), but that is an inference, not an observation - the
  # real cause was masked as Plug.Conn.AlreadySentError and has never been seen.
  # Logging at :error surfaces it in Sentry for one confirm window. Next step:
  # once it is confirmed to be a benign transport close, remove the log and close
  # silently, matching the no-log {:error, :closed} branch above. If it turns out
  # to be anything else, that is a real bug to fix rather than a disconnect to
  # swallow.
  defp stream_until_closed(conn, session_id, user_id, opts) do
    message_pump(conn, session_id, user_id, opts)
  catch
    kind, reason ->
      Logger.error("Hologram SSE stream closed by a write error",
        crash_reason: {Exception.normalize(kind, reason, __STACKTRACE__), __STACKTRACE__}
      )

      conn
  end
end
