defmodule Hologram.Realtime.SSE do
  @moduledoc false

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.DB.Oplog
  alias Hologram.Mutation.Record
  alias Hologram.Policy.Edges
  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Reflection
  alias Hologram.Runtime.ReplicaIdentity
  alias Hologram.Runtime.Session
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Handshake, as: SyncHandshake
  alias Hologram.Sync.Session, as: SyncSession

  # Read only when the host app enables the attach-delay seam - see maybe_delay_attach/1.
  @attach_delay_cookie "hologram_sse_attach_delay_ms"

  @heartbeat_interval_ms 15_000
  @max_heap_size_words 1_000_000
  @receipts_refresh_interval_ms 12 * 60 * 60 * 1000

  @doc """
  Returns the name of the cookie carrying the test-only attach delay.

  Honored only when the host app sets `:__sse_attach_delay_enabled__`, so it has
  no effect in production. See `maybe_delay_attach/1`.
  """
  @spec attach_delay_cookie() :: String.t()
  def attach_delay_cookie, do: @attach_delay_cookie

  @doc """
  Builds the SSE event-stream chunk for an `action` broadcast: the standard
  `event:`/`id:`/`data:` framing with the given id and the encoded `%Action{}`
  struct as the data payload.
  """
  @spec encode_action_envelope(integer, Action.t()) :: String.t()
  def encode_action_envelope(id, %Action{} = action) do
    {:ok, data} = Encoder.encode_client_term(action)
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
    {:ok, data} = Encoder.encode_client_term(receipts)
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
    {:ok, data} = Encoder.encode_client_term({action_name, params, cids})
    "event: broadcast\nid: #{id}\ndata: #{data}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk for a `drop_sub_receipts` event: the
  standard `event:`/`id:`/`data:` framing with the given id and the encoded
  list of `{channel, cid}` keys as the data payload.
  """
  @spec encode_drop_sub_receipts_envelope(integer, [{any, String.t()}]) :: String.t()
  def encode_drop_sub_receipts_envelope(id, keys) do
    {:ok, data} = Encoder.encode_client_term(keys)
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
    {:ok, data} = Encoder.encode_client_term(receipts)
    "event: refresh_sub_receipts\nid: #{id}\ndata: #{data}\n\n"
  end

  # Public so tests can read what a client said without standing up a stream to say it on.
  @doc false
  @spec greeting(Plug.Conn.t()) :: map
  def greeting(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params do
      %{"model_hash" => model_hash, "page" => page, "protocol_version" => protocol_version} =
          params ->
        %{
          cursor: params["cursor"],
          model_hash: model_hash,
          page: page_module(page),
          protocol_version: parse_protocol_version(protocol_version),
          replica_id: params["replica_id"],
          replica_token: params["replica_token"]
        }

      # A client built before any of this existed says nothing about sync, and keeps its stream.
      _no_greeting ->
        %{}
    end
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
          | {:cont, Plug.Conn.t(), term | nil, term | nil, pid | nil}
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

      {:sync_deltas, cursor, deltas, applied_seq} ->
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = Frame.encode_deltas_envelope(id, cursor, deltas, applied_seq)

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end

      {:sync_reload, reason} ->
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = Frame.encode_reload_envelope(id, reason)

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end

      {:sync_resync, reason} ->
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = Frame.encode_resync_envelope(id, reason)

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end

      {:sync_synced, scope, cursor} ->
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = Frame.encode_synced_envelope(id, scope, cursor)

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end

      # A subscription granted from outside any handler. The binding is registered and
      # its receipt signed here rather than by the grantor, so the authorization carries
      # the identity this connection holds at delivery time.
      {:add_subscription, channel, cid} ->
        conn = Plug.Conn.fetch_query_params(conn)
        instance_id = conn.query_params["instance_id"]

        SubscriptionRegistry.apply_deltas(instance_id, [{channel, cid}], [], user_id)

        token = Receipt.issue(channel, cid, instance_id, user_id)
        id = System.unique_integer([:positive, :monotonic])
        chunk_data = encode_add_sub_receipts_envelope(id, [{channel, cid, token}])

        case Plug.Conn.chunk(conn, chunk_data) do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end

      # Deltas a node that does not hold this connection could not apply itself. The
      # instance id travels in the message rather than being read from the query params,
      # since the sender identified the connection, not this stream.
      #
      # Only the node holding the connection answers. Being subscribed to the announce
      # topic implies holding the entry in every steady state, but not in recovery ones
      # (a registry restart empties the table while streams live on) - and applying
      # against a missing entry would park this pump for the whole attach window.
      # Staying silent leaves the ask to the requester's republish cadence instead.
      {:apply_deltas_remote, instance_id, adds, drops, authorizing_user_id, reply_to, waiter_ref} ->
        if SubscriptionRegistry.bindings_of(instance_id) do
          result =
            SubscriptionRegistry.apply_deltas(instance_id, adds, drops, authorizing_user_id)

          send(reply_to, {:apply_deltas_remote_reply, instance_id, waiter_ref, result})
        end

        {:cont, conn}

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
          {:cont, conn} ->
            {conn, sync_session} =
              restart_syncing(conn, Keyword.get(opts, :sync_session), new_user_id)

            {:cont, conn, new_session_id, new_user_id, sync_session}

          {:halt, conn} ->
            {:halt, conn}
        end

      :refresh_receipts ->
        case dispatch_receipts_refresh(conn) do
          {:cont, conn} ->
            schedule_receipts_refresh(receipts_refresh_interval_ms)
            {:cont, conn}

          {:halt, conn} ->
            {:halt, conn}
        end

      # A page render declares the complete subscription set, so the bindings are
      # replaced rather than folded. Nothing is answered - the renderer computed the
      # client's diff without the registry.
      {:replace_subscriptions, new_sub_keys, authorizing_user_id} ->
        conn = Plug.Conn.fetch_query_params(conn)
        instance_id = conn.query_params["instance_id"]

        SubscriptionRegistry.replace_bindings(instance_id, new_sub_keys, authorizing_user_id)

        {:cont, conn}

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

  # Public so tests can check what a greeting's identity is worth without standing up a stream.
  @doc false
  @spec verified_replica_id(map, Plug.Conn.t(), term | nil) :: String.t() | nil
  def verified_replica_id(greeting, conn, user_id) do
    replica_id = greeting[:replica_id]
    token = greeting[:replica_token]

    if is_binary(replica_id) and is_binary(token) and
         ReplicaIdentity.verify(token, replica_id, Session.get_session_id(conn), user_id) == :ok do
      replica_id
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

        # Announce topics are joined before the registry attach, so the window between
        # the connection becoming discoverable and this process listening does not
        # exist. Anything published in the meantime waits in the mailbox and is applied
        # once the pump starts, by which point the attach has folded in the handshake's
        # own bindings.
        {conn, sync_session} =
          conn
          |> subscribe_to_announce_topics()
          |> maybe_delay_attach()
          |> attach_validated_subscriptions(validated_bindings)
          |> prepare()
          |> start_syncing(user_id)

        message_pump(conn, session_id, user_id, [
          {:sync_session, sync_session} | message_pump_opts
        ])

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

  # Test-only seam. Holds the stream open before it attaches, so a test can put a
  # command on the wire while the instance still has no registry entry - the boot-time
  # race a subscription declared from a command has to survive. That race is otherwise
  # unreproducible over a local loop, where the attach reliably wins.
  #
  # Scoped by cookie rather than application env so concurrently running test files
  # cannot disturb each other, and gated on the host app opting in so a client can
  # never slow its own attach in production.
  defp maybe_delay_attach(initial_conn) do
    if Application.get_env(:hologram, :__sse_attach_delay_enabled__, false) do
      conn = Plug.Conn.fetch_cookies(initial_conn)

      with value when is_binary(value) <- conn.cookies[@attach_delay_cookie],
           {delay_ms, ""} when delay_ms > 0 <- Integer.parse(value) do
        Process.sleep(delay_ms)
      end

      conn
    else
      initial_conn
    end
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

      # A change of identity replaces the sync session as well as naming who the client now is,
      # so what the next turn is handed has to carry the new one.
      {:cont, conn, new_session_id, new_user_id, new_sync_session} ->
        opts = Keyword.put(opts, :sync_session, new_sync_session)

        message_pump(conn, new_session_id, new_user_id, opts)

      {:halt, conn} ->
        conn
    end
  end

  # What the client says about its own sync arrives on the stream's own request rather than
  # through the handshake stash: the page is its claim either way (what it names decides which
  # windows are kept, never what it may see of them), and the stash is a flat tuple gossiped
  # between nodes, which is not a shape to grow for a claim that needs no protecting.
  # A client arriving for the first time holds nothing and is simply filled. One coming back is
  # either told what it missed, or told to let go of what it holds - and is then filled the same
  # way a first arrival is. Deciding it here rather than in the session keeps the session a reader
  # of rounds and nothing else, and puts the answer beside the reload notice it stands next to.
  defp gap(nil, _user_id), do: {nil, nil}

  defp gap(cursor, user_id) do
    case Catchup.gap(cursor, user_id) do
      {:ok, effects, grants_then} ->
        {effects, grants_then}

      {:full_resync, reason} ->
        send(self(), {:sync_resync, reason})

        {nil, nil}
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

  # A page this build has never compiled stays the string it arrived as, which matches no window
  # and leaves the client with an empty session rather than an error.
  defp page_module(page) do
    String.to_existing_atom("Elixir." <> page)
  rescue
    ArgumentError -> page
  end

  defp parse_protocol_version(protocol_version) do
    case Integer.parse(protocol_version) do
      {version, ""} -> version
      _not_a_version -> protocol_version
    end
  end

  defp schedule_heartbeat(heartbeat_interval_ms) do
    Process.send_after(self(), :heartbeat, heartbeat_interval_ms)
  end

  defp schedule_receipts_refresh(interval_ms) do
    Process.send_after(self(), :refresh_receipts, interval_ms)
  end

  # The session is linked, so it goes when the connection does - what a client holds is only
  # worth keeping while there is a client to tell about it. Handed back so the connection can
  # reach it later: who the client IS can change while the stream stays open, and the session
  # decides what that client may see.
  #
  # `resume?` is false for a client being filled again from nothing, which is what a change of
  # identity leaves it needing - the place it named belongs to a store it has been told to drop.
  defp start_syncing(conn, user_id, resume? \\ true) do
    greeting = greeting(conn)

    case SyncHandshake.check(greeting) do
      {:sync, page, cursor} ->
        # Named rather than written inline as `resume? && gap(cursor, user_id)`: that answers
        # FALSE when it does not resume, and a session reads "no gap" from nil alone - anything
        # else and it sets about replaying something it cannot walk.
        {gap, grants_then} = if resume?, do: gap(cursor, user_id), else: {nil, nil}

        # What a rule reads besides its own row, so a row the gap never names can be judged again
        # when the row DECIDING it moved. Only for a returning client - one arriving with nothing
        # is sent every row it may see, so there is nothing to reach back for.
        #
        # Derived per resume rather than kept, for the reason `Fanout.route/2` derives per batch:
        # it follows the compiled model, which a live reload can change under a running node. A
        # connect already fills every window, which is where this cost belongs - never a per-frame
        # path.
        edges = if gap, do: Edges.derive(Reflection.list_entities())

        replica_id = verified_replica_id(greeting, conn, user_id)

        # Read HERE rather than in the session, so the database work of starting a stream stays in
        # the process that already does it - and so the session is a state machine over what it is
        # handed rather than a reader of its own.
        applied_seq = replica_id && Record.highest_confirmed_seq(replica_id)

        {:ok, session} =
          SyncSession.start_link(
            actor_user_id: user_id,
            applied_seq: applied_seq,
            client: self(),
            edges: edges,
            fill_place: {Oplog.current_xmin(), 0},
            gap: gap,
            grants_then: grants_then,
            page: page,
            replica_id: replica_id
          )

        {conn, session}

      {:reload, reason} ->
        send(self(), {:sync_reload, reason})

        {conn, nil}

      :no_sync ->
        {conn, nil}
    end
  end

  # A client whose identity changed holds rows it was given as someone else, and the session
  # serving it filters by the actor it was started with. Neither can be corrected in place: the
  # store is dropped through the door the client already has, and a session is started for who it
  # is now. Told to drop BEFORE the new one begins filling, since a self-send is ahead of anything
  # the new session will queue behind it.
  defp restart_syncing(conn, nil, _new_user_id), do: {conn, nil}

  defp restart_syncing(conn, session, new_user_id) do
    send(self(), {:sync_resync, :identity})

    :ok = GenServer.stop(session, :normal)

    start_syncing(conn, new_user_id, false)
  end
end
