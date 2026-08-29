defmodule Hologram.Realtime.SSETest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.SSE

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Sync.Frame
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module2, as: EntityModule2

  @server_only_token_js ~s'[Type.atom("token"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Entity.ServerOnly")], [Type.atom("attribute"), Type.atom("token")]])]'

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Handshake)
    start_supervised!(Handshake)

    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    :ok
  end

  defp conn_with_identities(opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)
    session = build_session(opts)

    :get
    |> Plug.Test.conn("/?instance_id=#{instance_id}")
    |> Plug.Test.init_test_session(session)
  end

  defp conn_with_instance_id(session \\ %{}) do
    instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

    session_id =
      Map.get(
        session,
        :hologram_session_id,
        "test-session-#{:erlang.unique_integer([:positive])}"
      )

    user_id = Map.get(session, :hologram_user_id)

    handshake_id = "test-handshake-#{:erlang.unique_integer([:positive])}"
    expires_at = System.system_time(:millisecond) + Handshake.stash_ttl_ms()
    Handshake.insert(handshake_id, [], {instance_id, session_id, user_id}, expires_at)

    session = Map.put(session, :hologram_session_id, session_id)

    :get
    |> Plug.Test.conn("/?instance_id=#{instance_id}&handshake_id=#{handshake_id}")
    |> Plug.Test.init_test_session(session)
  end

  defp build_session(opts) do
    session_id =
      Keyword.get(opts, :session_id, "test-session-#{:erlang.unique_integer([:positive])}")

    session = %{hologram_session_id: session_id}

    case Keyword.fetch(opts, :user_id) do
      {:ok, user_id} -> Map.put(session, :hologram_user_id, user_id)
      :error -> session
    end
  end

  # Plug.Test.Adapter sends `{:plug_conn, :sent}` to the owner on send_chunked.
  # Consume it so tests that drive process_message/2 directly see only the
  # messages they sent themselves.
  defp flush_plug_conn_sent do
    receive do
      {:plug_conn, :sent} -> :ok
    end
  end

  # Pulls the signed token out of an encoded add_sub_receipts chunk, which carries it as
  # the third element of each {channel, cid, token} tuple.
  defp extract_receipt_token(resp_body) do
    [_full_match, token] = Regex.run(~r/Type\.bitstring\("(SFMyNTY\.[^"]+)"\)/, resp_body)

    token
  end

  defp prepared_test_conn do
    conn =
      :get
      |> Plug.Test.conn("/")
      |> prepare()

    flush_plug_conn_sent()
    conn
  end

  defp prepared_test_conn_with_identities(opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)
    session = build_session(opts)

    conn =
      :get
      |> Plug.Test.conn("/?instance_id=#{instance_id}")
      |> Plug.Test.init_test_session(session)
      |> Plug.Conn.fetch_query_params()
      |> prepare()

    flush_plug_conn_sent()

    conn
  end

  defp stream_with_identities(stash_identity, claimed_identity) do
    handshake_id = "test-handshake-#{:erlang.unique_integer([:positive])}"

    Handshake.insert(
      handshake_id,
      [],
      stash_identity,
      System.system_time(:millisecond) + Handshake.stash_ttl_ms()
    )

    {instance_id, session_id, user_id} = claimed_identity

    session =
      if user_id do
        %{hologram_session_id: session_id, hologram_user_id: user_id}
      else
        %{hologram_session_id: session_id}
      end

    :get
    |> Plug.Test.conn("/?instance_id=#{instance_id}&handshake_id=#{handshake_id}")
    |> Plug.Test.init_test_session(session)
    |> stream(server_wait_ms: 50)
  end

  describe "encode_action_envelope/2" do
    test "wraps an encoded action in the SSE event envelope" do
      action = %Action{name: :my_action, target: "c1"}
      {:ok, encoded} = Encoder.encode_term(action)

      assert encode_action_envelope(42, action) == "event: action\nid: 42\ndata: #{encoded}\n\n"
    end

    test "replaces server-only attribute values in the action params with the sentinel" do
      row = %Module15{
        id: "test-id-sse-1",
        label: "Report",
        secret_note: "note_secret_v1",
        token: "tok_K3xR"
      }

      action = %Action{name: :my_action, params: %{row: row}, target: "c1"}

      envelope = encode_action_envelope(42, action)

      assert String.contains?(envelope, @server_only_token_js)
      refute String.contains?(envelope, "note_secret_v1")
      refute String.contains?(envelope, "tok_K3xR")
    end
  end

  describe "encode_add_sub_receipts_envelope/2" do
    test "wraps the receipts list in an add_sub_receipts SSE event envelope" do
      receipts = [{:notifications, "c1", "token-a"}]
      {:ok, encoded} = Encoder.encode_term(receipts)

      assert encode_add_sub_receipts_envelope(42, receipts) ==
               "event: add_sub_receipts\nid: 42\ndata: #{encoded}\n\n"
    end
  end

  describe "encode_broadcast_envelope/4" do
    test "wraps a single-cid payload in a broadcast SSE event envelope" do
      {:ok, encoded} = Encoder.encode_term({:append, %{text: "hi"}, ["chat"]})

      assert encode_broadcast_envelope(42, :append, %{text: "hi"}, ["chat"]) ==
               "event: broadcast\nid: 42\ndata: #{encoded}\n\n"
    end

    test "wraps a multi-cid payload in a broadcast SSE event envelope" do
      cids = ["chat", "sidebar", "minimap"]
      {:ok, encoded} = Encoder.encode_term({:append, %{text: "hi"}, cids})

      assert encode_broadcast_envelope(42, :append, %{text: "hi"}, cids) ==
               "event: broadcast\nid: 42\ndata: #{encoded}\n\n"
    end

    test "handles empty params" do
      {:ok, encoded} = Encoder.encode_term({:ping, %{}, ["page"]})

      assert encode_broadcast_envelope(1, :ping, %{}, ["page"]) ==
               "event: broadcast\nid: 1\ndata: #{encoded}\n\n"
    end

    test "replaces server-only attribute values in the broadcast params with the sentinel" do
      row = %Module15{
        id: "test-id-sse-2",
        label: "Report",
        secret_note: "note_secret_v2",
        token: "tok_M6zY"
      }

      envelope = encode_broadcast_envelope(42, :append, %{row: row}, ["chat"])

      assert String.contains?(envelope, @server_only_token_js)
      refute String.contains?(envelope, "note_secret_v2")
      refute String.contains?(envelope, "tok_M6zY")
    end
  end

  describe "encode_drop_sub_receipts_envelope/2" do
    test "wraps the keys list in a drop_sub_receipts SSE event envelope" do
      keys = [{:notifications, "c1"}]
      {:ok, encoded} = Encoder.encode_term(keys)

      assert encode_drop_sub_receipts_envelope(42, keys) ==
               "event: drop_sub_receipts\nid: 42\ndata: #{encoded}\n\n"
    end
  end

  describe "encode_refresh_sub_receipts_envelope/2" do
    test "wraps the receipts list in a refresh_sub_receipts SSE event envelope" do
      receipts = [{:notifications, "c1", "token-a"}]
      {:ok, encoded} = Encoder.encode_term(receipts)

      assert encode_refresh_sub_receipts_envelope(42, receipts) ==
               "event: refresh_sub_receipts\nid: 42\ndata: #{encoded}\n\n"
    end
  end

  describe "greeting/1" do
    defp sync_query_string(extra \\ "") do
      "/?model_hash=a3f9c2&page=MyApp.BoardPage&protocol_version=1" <> extra
    end

    test "reads what a client said about sync" do
      conn = Plug.Test.conn(:get, sync_query_string())

      assert greeting(conn) == %{
               cursor: nil,
               model_hash: "a3f9c2",
               page: MyApp.BoardPage,
               protocol_version: 1
             }
    end

    test "reads the place a returning client names" do
      conn = Plug.Test.conn(:get, sync_query_string("&cursor=g8uxAAAAZQ"))

      assert greeting(conn).cursor == "g8uxAAAAZQ"
    end

    test "reads nothing from a client that said nothing about sync" do
      conn = Plug.Test.conn(:get, "/?instance_id=whatever")

      assert greeting(conn) == %{}
    end
  end

  describe "prepare/1" do
    test "sets SSE response headers" do
      conn = Plug.Test.conn(:get, "/")
      result = prepare(conn)

      assert result.resp_headers == [
               {"cache-control", "no-cache"},
               {"connection", "keep-alive"},
               {"content-type", "text/event-stream"}
             ]
    end

    test "opens a chunked response with status 200" do
      conn = Plug.Test.conn(:get, "/")
      result = prepare(conn)

      assert result.state == :chunked
      assert result.status == 200
    end
  end

  describe "process_message/4 on {:add_sub_receipts, ...}" do
    test "pushes an add_sub_receipts SSE event" do
      conn = prepared_test_conn()
      receipts = [{:notifications, "c1", "token-a"}]
      send(self(), {:add_sub_receipts, receipts})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: add_sub_receipts\nid: "
      assert updated_conn.resp_body =~ "\ndata: "
    end
  end

  describe "process_message/4 on {:sync_deltas, ...}" do
    test "pushes a sync_deltas SSE event carrying the deltas" do
      conn = prepared_test_conn()
      row = EntityModule2.new(a: true, c: "first")

      # Built through the frame rather than by hand: a delta holds a row already written the way
      # the wire carries it, and JSON refuses to guess at a struct rather than encoding one badly.
      deltas = [Frame.put_entity(row)]

      send(self(), {:sync_deltas, "g8uxAAAAZQ", deltas})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: sync_deltas\nid: "
      assert updated_conn.resp_body =~ ~s["c":"first"]

      # The place the client hands back on reconnect.
      assert updated_conn.resp_body =~ ~s["cursor":"g8uxAAAAZQ"]
    end

    # The field is on the wire before anything fills it, so a client can be taught to read it
    # while every frame still says nothing.
    test "pushes a frame naming no applied batch of the receiving replica" do
      conn = prepared_test_conn()

      send(self(), {:sync_deltas, "g8uxAAAAZQ", []})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ ~s["applied_seq":null]
    end
  end

  describe "process_message/4 on {:sync_reload, ...}" do
    test "pushes a sync_reload SSE event naming what disagreed" do
      conn = prepared_test_conn()
      send(self(), {:sync_reload, :model_hash})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: sync_reload\nid: "
      assert updated_conn.resp_body =~ ~s["reason":"model_hash"]
    end
  end

  describe "process_message/4 on {:sync_resync, reason}" do
    test "pushes a sync_resync SSE event" do
      conn = prepared_test_conn()
      send(self(), {:sync_resync, :retention})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: sync_resync\nid: "
      assert updated_conn.resp_body =~ ~s["reason":"retention"]
    end
  end

  describe "process_message/4 on {:sync_synced, scope}" do
    test "pushes a synced SSE event" do
      conn = prepared_test_conn()
      send(self(), {:sync_synced, :page})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: synced\nid: "
    end

    test "carries the scope the client may now answer from its own store" do
      conn = prepared_test_conn()
      send(self(), {:sync_synced, :all})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ ~s["scope":"all"]
    end
  end

  describe "process_message/4 on {:add_subscription, ...}" do
    test "registers the binding under the connection's current user_id" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:add_subscription, :room_a, "page"})

      process_message(conn, "test-session-id", "test-user-id")

      assert SubscriptionRegistry.bindings_of(instance_id) == %{
               {:room_a, "page"} => "test-user-id"
             }
    end

    test "pushes an add_sub_receipts SSE event for the granted binding" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:add_subscription, :room_a, "page"})

      {:cont, updated_conn} = process_message(conn, "test-session-id", "test-user-id")

      assert updated_conn.resp_body =~ "event: add_sub_receipts\nid: "
      assert updated_conn.resp_body =~ "\ndata: "
    end

    test "signs the pushed receipt for this connection and its current identity" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:add_subscription, :room_a, "page"})

      {:cont, updated_conn} = process_message(conn, "test-session-id", "test-user-id")

      {:ok, receipt} =
        updated_conn.resp_body
        |> extract_receipt_token()
        |> Receipt.verify()

      assert receipt.channel == :room_a
      assert receipt.cid == "page"
      assert receipt.instance_id == instance_id
      assert receipt.user_id == "test-user-id"
    end

    test "signs the receipt for an anonymous connection with a nil user_id" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:add_subscription, :room_a, "page"})

      {:cont, updated_conn} = process_message(conn, "test-session-id", nil)

      {:ok, receipt} =
        updated_conn.resp_body
        |> extract_receipt_token()
        |> Receipt.verify()

      assert receipt.user_id == nil
      assert SubscriptionRegistry.bindings_of(instance_id) == %{{:room_a, "page"} => nil}
    end

    test "emits the zero-crossing for the granted channel" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:add_subscription, :room_a, "page"})

      process_message(conn, "test-session-id", "test-user-id")

      assert_receive {:sub, :room_a}
    end
  end

  describe "process_message/4 on {:apply_deltas_remote, ...}" do
    test "applies the deltas to the addressed instance's bindings" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn()

      send(
        self(),
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [], "test-user-id", self(),
         make_ref()}
      )

      process_message(conn, nil, nil)

      assert SubscriptionRegistry.bindings_of(instance_id) == %{
               {:room_a, "page"} => "test-user-id"
             }
    end

    test "replies to the requesting process with the applied deltas" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn()
      waiter_ref = make_ref()

      send(
        self(),
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [], "test-user-id", self(),
         waiter_ref}
      )

      process_message(conn, nil, nil)

      assert_receive {:apply_deltas_remote_reply, ^instance_id, ^waiter_ref,
                      {[{:room_a, "page"}], []}}
    end

    test "replies with the idempotence-filtered deltas, not the requested ones" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      SubscriptionRegistry.apply_deltas(instance_id, [{:room_a, "page"}], [], "test-user-id")

      # Seeding the binding emits a zero-crossing to this process. Consume it, or the
      # pump's {:sub, channel} clause matches it ahead of the message under test.
      assert_receive {:sub, :room_a}

      conn = prepared_test_conn()
      waiter_ref = make_ref()

      # Re-adds a binding that is already present and drops one that is absent, so both
      # requested deltas filter out.
      send(
        self(),
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [{:room_b, "page"}],
         "test-user-id", self(), waiter_ref}
      )

      process_message(conn, nil, nil)

      assert_receive {:apply_deltas_remote_reply, ^instance_id, ^waiter_ref, {[], []}}
    end

    test "registers the binding once when the same request is delivered twice" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn()
      waiter_ref = make_ref()

      request =
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [], "test-user-id", self(),
         waiter_ref}

      send(self(), request)
      send(self(), request)

      process_message(conn, nil, nil)
      assert_receive {:sub, :room_a}
      process_message(conn, nil, nil)

      assert SubscriptionRegistry.bindings_of(instance_id) == %{
               {:room_a, "page"} => "test-user-id"
             }

      # The first answer carries the applied deltas, the duplicate answers filtered-empty
      # - and the requester drops whichever arrives after its waiter is gone.
      assert_receive {:apply_deltas_remote_reply, ^instance_id, ^waiter_ref,
                      {[{:room_a, "page"}], []}}

      assert_receive {:apply_deltas_remote_reply, ^instance_id, ^waiter_ref, {[], []}}

      refute_receive {:sub, :room_a}
    end

    test "emits the zero-crossing for a channel the deltas newly bind" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn()

      send(
        self(),
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [], "test-user-id", self(),
         make_ref()}
      )

      process_message(conn, nil, nil)

      assert_receive {:sub, :room_a}
    end

    test "continues the message pump with the conn untouched" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn()

      send(
        self(),
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [], "test-user-id", self(),
         make_ref()}
      )

      assert process_message(conn, nil, nil) == {:cont, conn}
    end

    test "stays silent when this node does not hold the connection" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      conn = prepared_test_conn()
      waiter_ref = make_ref()

      send(
        self(),
        {:apply_deltas_remote, instance_id, [{:room_a, "page"}], [], "test-user-id", self(),
         waiter_ref}
      )

      assert process_message(conn, nil, nil) == {:cont, conn}

      assert SubscriptionRegistry.bindings_of(instance_id) == nil
      refute_receive {:apply_deltas_remote_reply, ^instance_id, ^waiter_ref, _result}
    end
  end

  describe "process_message/4 on {:broadcast_action, ...}" do
    test "emits one bundled event: broadcast chunk carrying all matching cids" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      channel = {:room, 1}

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{channel, "chat"}, nil}, {{channel, "sidebar"}, nil}]
      )

      send(self(), {:broadcast_action, channel, :my_action, %{}, []})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: broadcast\n"

      # Only one event chunk total (the bundled one), not one per cid.
      assert length(String.split(updated_conn.resp_body, "event: broadcast\n", trim: true)) == 1

      {:ok, encoded} = Encoder.encode_term({:my_action, %{}, ["chat", "sidebar"]})
      assert updated_conn.resp_body =~ "data: #{encoded}\n"
    end

    test "emits nothing when no binding matches the broadcast's channel" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{{:room, 2}, "chat"}, nil}]
      )

      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, []})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body == ""
    end

    test "emits nothing when no registry entry exists for the instance" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, []})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body == ""
    end

    test "drops the broadcast when the conn's instance identity is in excluded_identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{{:room, 1}, "chat"}, nil}]
      )

      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, [{:instance, instance_id}]})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body == ""
    end

    test "drops the broadcast when the connection's session identity is in excluded_identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id, session_id: session_id)

      SubscriptionRegistry.attach_connection(
        instance_id,
        session_id,
        nil,
        self(),
        [{{{:room, 1}, "chat"}, nil}]
      )

      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, [{:session, session_id}]})

      {:cont, updated_conn} = process_message(conn, session_id, nil)

      assert updated_conn.resp_body == ""
    end

    test "drops the broadcast when the connection's user identity is in excluded_identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id, user_id: user_id)

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        user_id,
        self(),
        [{{{:room, 1}, "chat"}, nil}]
      )

      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, [{:user, user_id}]})

      {:cont, updated_conn} = process_message(conn, nil, user_id)

      assert updated_conn.resp_body == ""
    end

    test "excludes against the reconciled loop-state identity, not the conn's attach-time identity" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id, user_id: "stale-user")

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        "fresh-user",
        self(),
        [{{{:room, 1}, "chat"}, nil}]
      )

      # The connection logged in mid-stream: the conn still carries the
      # attach-time user ("stale-user"), but the loop state holds "fresh-user".
      # Excluding the reconciled user drops the broadcast.
      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, [{:user, "fresh-user"}]})

      {:cont, updated_conn} = process_message(conn, nil, "fresh-user")

      assert updated_conn.resp_body == ""
    end

    test "does not exclude against the conn's stale attach-time identity" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id, user_id: "stale-user")

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        "fresh-user",
        self(),
        [{{{:room, 1}, "chat"}, nil}]
      )

      # Excluding the conn's stale attach-time user must NOT drop the broadcast:
      # the reconciled loop-state identity is "fresh-user".
      send(self(), {:broadcast_action, {:room, 1}, :my_action, %{}, [{:user, "stale-user"}]})

      {:cont, updated_conn} = process_message(conn, nil, "fresh-user")

      assert updated_conn.resp_body =~ "event: broadcast\n"
    end

    test "dispatches when excluded_identities contains identities that don't match the conn" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{{:room, 1}, "chat"}, nil}]
      )

      send(
        self(),
        {:broadcast_action, {:room, 1}, :my_action, %{}, [{:instance, "other-instance"}]}
      )

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: broadcast\n"
    end
  end

  describe "process_message/4 on {:close, ...}" do
    test "halts" do
      conn = prepared_test_conn()
      send(self(), {:close, :superseded})

      assert {:halt, ^conn} = process_message(conn, nil, nil)
    end
  end

  describe "process_message/4 on {:drop_channel, ...}" do
    test "drops every cid bound to the channel and pushes a drop_sub_receipts SSE event" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [
          {{:notifications, "c1"}, nil},
          {{:notifications, "c2"}, nil},
          {{:other_channel, "c3"}, nil}
        ]
      )

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:drop_channel, :notifications})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: drop_sub_receipts\nid: "
      assert SubscriptionRegistry.bindings_of(instance_id) == %{{:other_channel, "c3"} => nil}
    end

    test "unsubscribes from the channel's PubSub topic" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.channel_topic(:notifications)

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{:notifications, "c1"}, nil}]
      )

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:drop_channel, :notifications})

      process_message(conn, nil, nil)

      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      refute_receive :hello
    end

    test "is a no-op when no bindings exist for the channel" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{:other_channel, "c1"}, nil}]
      )

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:drop_channel, :notifications})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      refute updated_conn.resp_body =~ "event: drop_sub_receipts"
      assert SubscriptionRegistry.bindings_of(instance_id) == %{{:other_channel, "c1"} => nil}
    end
  end

  describe "process_message/4 on {:drop_sub_receipts, ...}" do
    test "drops the binding and pushes a drop_sub_receipts SSE event" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{:notifications, "c1"}, nil}]
      )

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:drop_sub_receipts, [{:notifications, "c1"}]})

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: drop_sub_receipts\nid: "
      assert SubscriptionRegistry.bindings_of(instance_id) == %{}
    end

    test "unsubscribes from the zero-crossing channel's PubSub topic" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.channel_topic(:notifications)

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{:notifications, "c1"}, nil}]
      )

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:drop_sub_receipts, [{:notifications, "c1"}]})

      process_message(conn, nil, nil)

      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      refute_receive :hello
    end
  end

  describe "process_message/4 on :heartbeat" do
    test "writes an SSE comment line" do
      conn = prepared_test_conn()
      send(self(), :heartbeat)

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body == ":\n\n"
    end

    test "schedules the next heartbeat after handling one" do
      conn = prepared_test_conn()
      send(self(), :heartbeat)

      process_message(conn, nil, nil, heartbeat_interval_ms: 30)

      assert_receive :heartbeat
    end
  end

  describe "process_message/4 on {:identity_changed, ...}" do
    test "carries the new identity in the return tuple" do
      conn = Plug.Conn.fetch_query_params(prepared_test_conn())
      send(self(), {:identity_changed, "new-session-id", 7})

      assert {:cont, ^conn, "new-session-id", 7, _sync_session} =
               process_message(conn, "old-session-id", nil)
    end

    # Who the client is decides what its session lets through, and that is fixed when the session
    # starts. A stream that stays open across a login, a logout or a switch would otherwise go on
    # filtering rows as whoever was there before, and the client would go on holding them.
    test "sends the client through the resync door when its identity changes" do
      conn = Plug.Conn.fetch_query_params(prepared_test_conn())
      old_session = start_supervised!({Agent, fn -> :sync_session end})

      send(self(), {:identity_changed, "session-1", 8})

      {:cont, _conn, _session_id, _user_id, _sync_session} =
        process_message(conn, "session-1", 7, sync_session: old_session)

      assert_received {:sync_resync, :identity}
    end

    test "stops the session that was serving the identity it replaced" do
      conn = Plug.Conn.fetch_query_params(prepared_test_conn())
      old_session = start_supervised!({Agent, fn -> :sync_session end})
      ref = Process.monitor(old_session)

      send(self(), {:identity_changed, "session-1", 8})

      process_message(conn, "session-1", 7, sync_session: old_session)

      assert_receive {:DOWN, ^ref, :process, ^old_session, :normal}
    end

    # A stream carrying no sync at all - a client built before any of it, or one whose build has
    # no data model - has nothing to rescope, and must not be disturbed for it.
    test "leaves a connection that is not syncing alone" do
      conn = Plug.Conn.fetch_query_params(prepared_test_conn())
      send(self(), {:identity_changed, "session-1", 8})

      assert {:cont, _conn, _session_id, _user_id, nil} =
               process_message(conn, "session-1", 7)

      refute_received {:sync_resync, _reason}
    end

    test "subscribes to the user identity topic on login (nil -> 7)" do
      conn = prepared_test_conn()
      send(self(), {:identity_changed, "session-1", 7})

      process_message(conn, "session-1", nil)

      user_topic = Realtime.identity_topic(:user, 7)
      Phoenix.PubSub.broadcast(Hologram.PubSub, user_topic, :hello)

      assert_receive :hello
    end

    test "unsubscribes from the user identity topic on logout (7 -> nil)" do
      conn = prepared_test_conn()
      user_topic = Realtime.identity_topic(:user, 7)
      Phoenix.PubSub.subscribe(Hologram.PubSub, user_topic)

      send(self(), {:identity_changed, "session-1", nil})

      process_message(conn, "session-1", 7)

      Phoenix.PubSub.broadcast(Hologram.PubSub, user_topic, :hello)

      refute_receive :hello
    end

    test "swaps the user identity topic on account switch (7 -> 8)" do
      conn = prepared_test_conn()
      old_topic = Realtime.identity_topic(:user, 7)
      new_topic = Realtime.identity_topic(:user, 8)

      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      send(self(), {:identity_changed, "session-1", 8})

      process_message(conn, "session-1", 7)

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello_old)
      Phoenix.PubSub.broadcast(Hologram.PubSub, new_topic, :hello_new)

      refute_receive :hello_old
      assert_receive :hello_new
    end

    test "swaps the session identity topic on session rotation (S -> S' with user_id unchanged)" do
      conn = prepared_test_conn()
      old_topic = Realtime.identity_topic(:session, "session-old")
      new_topic = Realtime.identity_topic(:session, "session-new")

      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      send(self(), {:identity_changed, "session-new", 7})

      process_message(conn, "session-old", 7)

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello_old)
      Phoenix.PubSub.broadcast(Hologram.PubSub, new_topic, :hello_new)

      refute_receive :hello_old
      assert_receive :hello_new
    end

    test "updates the registry's identity record" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(instance_id, "old-session", 7, self(), [])

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:identity_changed, "new-session", 8})

      process_message(conn, "old-session", 7)

      assert SubscriptionRegistry.identity_of(instance_id) == {"new-session", 8}
    end

    test "pushes a drop_sub_receipts SSE event when user_id change drops bindings" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(
        instance_id,
        "session-1",
        7,
        self(),
        [{{:notifications, "c1"}, 7}]
      )

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:identity_changed, "session-1", 8})

      {:cont, updated_conn, _session, _user, _sync_session} =
        process_message(conn, "session-1", 7)

      assert updated_conn.resp_body =~ "event: drop_sub_receipts\nid: "
      assert SubscriptionRegistry.bindings_of(instance_id) == %{}
    end

    test "does not push a drop_sub_receipts SSE event on session rotation alone" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(
        instance_id,
        "session-old",
        7,
        self(),
        [{{:notifications, "c1"}, 7}]
      )

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:identity_changed, "session-new", 7})

      {:cont, updated_conn, _session, _user, _sync_session} =
        process_message(conn, "session-old", 7)

      refute updated_conn.resp_body =~ "event: drop_sub_receipts"
      assert SubscriptionRegistry.bindings_of(instance_id) == %{{:notifications, "c1"} => 7}
    end

    test "unsubscribes from the zero-crossing channel's PubSub topic on identity drop" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.channel_topic(:notifications)

      SubscriptionRegistry.attach_connection(
        instance_id,
        "session-1",
        7,
        self(),
        [{{:notifications, "c1"}, 7}]
      )

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:identity_changed, "session-1", 8})

      process_message(conn, "session-1", 7)

      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      refute_receive :hello
    end
  end

  describe "process_message/4 on :refresh_receipts" do
    test "pushes a refresh_sub_receipts SSE event when the instance has bindings" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      SubscriptionRegistry.attach_connection(
        instance_id,
        nil,
        nil,
        self(),
        [{{:notifications, "c1"}, nil}]
      )

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), :refresh_receipts)

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body =~ "event: refresh_sub_receipts\nid: "
      assert updated_conn.resp_body =~ "\ndata: "
    end

    test "writes nothing when the instance has no bindings" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), :refresh_receipts)

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body == ""
    end

    test "schedules the next refresh after handling one" do
      conn = prepared_test_conn()
      send(self(), :refresh_receipts)

      process_message(conn, nil, nil, receipts_refresh_interval_ms: 30)

      assert_receive :refresh_receipts
    end
  end

  describe "process_message/4 on {:replace_subscriptions, ...}" do
    test "replaces the bindings of the conn's instance" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      SubscriptionRegistry.apply_deltas(instance_id, [{:room_a, "page"}], [], "test-user-id")

      # Seeding the binding emits a zero-crossing to this process. Consume it, or the
      # pump's {:sub, channel} clause matches it ahead of the message under test.
      assert_receive {:sub, :room_a}

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:replace_subscriptions, [{:room_b, "page"}], "test-user-id"})

      process_message(conn, nil, nil)

      assert SubscriptionRegistry.bindings_of(instance_id) == %{
               {:room_b, "page"} => "test-user-id"
             }
    end

    test "emits the zero-crossings the replacement implies" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:replace_subscriptions, [{:room_a, "page"}], "test-user-id"})

      process_message(conn, nil, nil)

      assert_receive {:sub, :room_a}
    end

    test "continues the message pump" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      :ok = SubscriptionRegistry.register_connection(instance_id, self())

      conn = prepared_test_conn_with_identities(instance_id: instance_id)
      send(self(), {:replace_subscriptions, [{:room_a, "page"}], "test-user-id"})

      assert {:cont, _updated_conn} = process_message(conn, nil, nil)
    end
  end

  describe "process_message/4 on {:sub, ...}" do
    test "subscribes to the channel's PubSub topic" do
      conn = prepared_test_conn()
      send(self(), {:sub, :notifications})

      {:cont, _updated_conn} = process_message(conn, nil, nil)

      topic = Realtime.channel_topic(:notifications)
      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      assert_receive :hello
    end
  end

  describe "process_message/4 on {:unsub, ...}" do
    test "unsubscribes from the channel's PubSub topic" do
      conn = prepared_test_conn()
      topic = Realtime.channel_topic(:notifications)

      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)
      send(self(), {:unsub, :notifications})

      {:cont, _updated_conn} = process_message(conn, nil, nil)

      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      refute_receive :hello
    end
  end

  describe "process_message/4 on unknown messages" do
    test "continues without writing" do
      conn = prepared_test_conn()
      send(self(), :some_unknown_message)

      {:cont, updated_conn} = process_message(conn, nil, nil)

      assert updated_conn.resp_body == ""
    end
  end

  describe "attach_validated_subscriptions/2" do
    test "round-trips the validated bindings into the registry" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = conn_with_identities(instance_id: instance_id)

      bindings = [{{:notifications, "c1"}, nil}]

      attach_validated_subscriptions(conn, bindings)

      assert SubscriptionRegistry.bindings_of(instance_id) == %{{:notifications, "c1"} => nil}
    end

    test "subscribes to every distinct validated channel" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = conn_with_identities(instance_id: instance_id)

      bindings = [
        {{:notifications, "c1"}, nil},
        {{{:room, "lobby"}, "c2"}, nil}
      ]

      attach_validated_subscriptions(conn, bindings)

      topic_1 = Realtime.channel_topic(:notifications)
      Phoenix.PubSub.broadcast(Hologram.PubSub, topic_1, :hello_atom)

      topic_2 = Realtime.channel_topic({:room, :lobby})
      Phoenix.PubSub.broadcast(Hologram.PubSub, topic_2, :hello_tuple)

      assert_receive :hello_atom
      assert_receive :hello_tuple
    end

    test "subscribes once per channel even when multiple cids bind to the same channel" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = conn_with_identities(instance_id: instance_id)

      bindings = [
        {{:notifications, "c1"}, nil},
        {{:notifications, "c2"}, nil},
        {{:notifications, "c3"}, nil}
      ]

      attach_validated_subscriptions(conn, bindings)

      topic = Realtime.channel_topic(:notifications)
      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      assert_receive :hello
      refute_receive :hello
    end

    test "creates a registry entry but does not subscribe when validated_bindings is empty" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = conn_with_identities(instance_id: instance_id)

      attach_validated_subscriptions(conn, [])

      assert SubscriptionRegistry.bindings_of(instance_id) == %{}

      topic = Realtime.channel_topic(:notifications)
      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      refute_receive :hello
    end

    test "attaches with nil session_id and user_id when the conn has none" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

      conn =
        :get
        |> Plug.Test.conn("/?instance_id=#{instance_id}")
        |> Plug.Test.init_test_session(%{})

      attach_validated_subscriptions(conn, [{{:notifications, "c1"}, nil}])

      assert SubscriptionRegistry.identity_of(instance_id) == {nil, nil}

      topic = Realtime.channel_topic(:notifications)
      Phoenix.PubSub.broadcast(Hologram.PubSub, topic, :hello)

      assert_receive :hello
    end
  end

  describe "build_refresh_receipts/2" do
    test "returns an empty list when bindings is empty" do
      assert build_refresh_receipts("test-instance-id", %{}) == []
    end

    test "produces one {channel, cid, token} triple per binding" do
      bindings = %{
        {:notifications, "c1"} => nil,
        {{:room, "lobby"}, "c2"} => "user-7"
      }

      result = build_refresh_receipts("test-instance-id", bindings)

      assert length(result) == 2

      Enum.each(result, fn triple ->
        assert {channel, cid, token} = triple
        assert channel in [:notifications, {:room, "lobby"}]
        assert cid in ["c1", "c2"]
        assert is_binary(token)
      end)
    end

    test "each token round-trips channel, cid, instance_id, and the binding's authorizing_user_id" do
      bindings = %{
        {:notifications, "c1"} => nil,
        {{:room, "lobby"}, "c2"} => "user-7"
      }

      result = build_refresh_receipts("test-instance-id", bindings)

      receipts =
        Enum.map(result, fn {_channel, _cid, token} ->
          {:ok, receipt} = Receipt.verify(token)
          receipt
        end)

      anonymous = Enum.find(receipts, &(&1.channel == :notifications))
      assert anonymous.cid == "c1"
      assert anonymous.instance_id == "test-instance-id"
      assert anonymous.user_id == nil

      authenticated = Enum.find(receipts, &(&1.channel == {:room, "lobby"}))
      assert authenticated.cid == "c2"
      assert authenticated.instance_id == "test-instance-id"
      assert authenticated.user_id == "user-7"
    end
  end

  describe "maybe_reconcile_identity_subs/3" do
    test "is a no-op when both old and new are nil" do
      :ok = maybe_reconcile_identity_subs(:user, nil, nil)

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.identity_topic(:user, "anything"),
        :hello
      )

      refute_receive :hello
    end

    test "is a no-op when old and new are the same value" do
      :ok = maybe_reconcile_identity_subs(:session, "session-a", "session-a")

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.identity_topic(:session, "session-a"),
        :hello
      )

      refute_receive :hello
    end

    test "subscribes to the new topic when old is nil and new is non-nil" do
      maybe_reconcile_identity_subs(:user, nil, 7)

      Phoenix.PubSub.broadcast(Hologram.PubSub, Realtime.identity_topic(:user, 7), :hello)

      assert_receive :hello
    end

    test "unsubscribes from the old topic when old is non-nil and new is nil" do
      old_topic = Realtime.identity_topic(:user, 7)
      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      maybe_reconcile_identity_subs(:user, 7, nil)

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello)

      refute_receive :hello
    end

    test "unsubscribes from the old topic and subscribes to the new topic when both differ" do
      old_topic = Realtime.identity_topic(:user, 7)
      new_topic = Realtime.identity_topic(:user, 8)

      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      maybe_reconcile_identity_subs(:user, 7, 8)

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello_old)
      Phoenix.PubSub.broadcast(Hologram.PubSub, new_topic, :hello_new)

      refute_receive :hello_old
      assert_receive :hello_new
    end
  end

  describe "maybe_reconcile_session_announce_sub/2" do
    test "unsubscribes from the old announce topic and subscribes to the new one on session change" do
      old_topic = Realtime.session_announce_topic("s-old")
      new_topic = Realtime.session_announce_topic("s-new")

      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      maybe_reconcile_session_announce_sub("s-old", "s-new")

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello_old)
      Phoenix.PubSub.broadcast(Hologram.PubSub, new_topic, :hello_new)

      refute_receive :hello_old
      assert_receive :hello_new
    end
  end

  describe "maybe_reconcile_user_announce_sub/2" do
    test "unsubscribes from the old user announce topic and subscribes to the new one on user change" do
      old_topic = Realtime.user_announce_topic("u-old")
      new_topic = Realtime.user_announce_topic("u-new")

      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      maybe_reconcile_user_announce_sub("u-old", "u-new")

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello_old)
      Phoenix.PubSub.broadcast(Hologram.PubSub, new_topic, :hello_new)

      refute_receive :hello_old
      assert_receive :hello_new
    end

    test "subscribes to the new user announce topic on login (nil -> user)" do
      new_topic = Realtime.user_announce_topic("u-new")

      maybe_reconcile_user_announce_sub(nil, "u-new")

      Phoenix.PubSub.broadcast(Hologram.PubSub, new_topic, :hello)

      assert_receive :hello
    end

    test "unsubscribes from the old user announce topic on logout (user -> nil)" do
      old_topic = Realtime.user_announce_topic("u-old")
      Phoenix.PubSub.subscribe(Hologram.PubSub, old_topic)

      maybe_reconcile_user_announce_sub("u-old", nil)

      Phoenix.PubSub.broadcast(Hologram.PubSub, old_topic, :hello)

      refute_receive :hello
    end
  end

  describe "stream/2" do
    test "returns 4xx when no handshake matches within the wait budget" do
      conn =
        :get
        |> Plug.Test.conn("/?instance_id=test-instance-id&handshake_id=unknown-handshake-id")
        |> Plug.Test.init_test_session(%{hologram_session_id: "test-session-id"})

      result = stream(conn, server_wait_ms: 50)

      assert result.halted == true
      assert result.status == 400
    end

    test "returns 4xx when the claimed instance_id differs from the stashed identity" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      result =
        stream_with_identities(
          {"stashed-instance", session_id, nil},
          {"different-instance", session_id, nil}
        )

      assert result.halted == true
      assert result.status == 400
      assert result.resp_body == "Handshake identity mismatch"
    end

    test "returns 4xx when the claimed session_id differs from the stashed identity (same user_id)" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"

      result =
        stream_with_identities(
          {instance_id, "stashed-session", user_id},
          {instance_id, "different-session", user_id}
        )

      assert result.halted == true
      assert result.status == 400
      assert result.resp_body == "Handshake identity mismatch"
    end

    test "returns 4xx when the claimed user_id differs from the stashed identity" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      result =
        stream_with_identities(
          {instance_id, session_id, "stashed-user"},
          {instance_id, session_id, "different-user"}
        )

      assert result.halted == true
      assert result.status == 400
      assert result.resp_body == "Handshake identity mismatch"
    end

    test "returns 4xx when the claimed identity is anonymous but the stash was authenticated" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      result =
        stream_with_identities(
          {instance_id, session_id, "stashed-user"},
          {instance_id, session_id, nil}
        )

      assert result.halted == true
      assert result.status == 400
      assert result.resp_body == "Handshake identity mismatch"
    end

    test "returns 4xx when the claimed identity is authenticated but the stash was anonymous" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      result =
        stream_with_identities(
          {instance_id, session_id, nil},
          {instance_id, session_id, "claimed-user"}
        )

      assert result.halted == true
      assert result.status == 400
      assert result.resp_body == "Handshake identity mismatch"
    end

    test "applies an announce message published before the connection attaches" do
      Application.put_env(:hologram, :__sse_attach_delay_enabled__, true)
      on_exit(fn -> Application.delete_env(:hologram, :__sse_attach_delay_enabled__) end)

      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      handshake_id = "test-handshake-#{:erlang.unique_integer([:positive])}"
      expires_at = System.system_time(:millisecond) + Handshake.stash_ttl_ms()

      Handshake.insert(handshake_id, [], {instance_id, session_id, nil}, expires_at)

      conn =
        :get
        |> Plug.Test.conn("/?instance_id=#{instance_id}&handshake_id=#{handshake_id}")
        |> Plug.Test.init_test_session(%{hologram_session_id: session_id})
        # The window under test is the attach delay, and both the assertion and the
        # publish below have to land inside it. A second is long enough that a stall
        # able to close it early would be breaking most of this suite too, and it is
        # paid once, by this test alone.
        |> Plug.Test.put_req_cookie(attach_delay_cookie(), "1000")

      pid = spawn(fn -> stream(conn, server_wait_ms: 200) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      topic = Realtime.instance_announce_topic(instance_id)
      wait_until(fn -> Registry.lookup(Hologram.PubSub, topic) != [] end)

      # Listening already, attached not yet. Without this the test would still pass with
      # the publish landing after the attach, proving nothing about the window.
      assert SubscriptionRegistry.bindings_of(instance_id) == nil

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        topic,
        {:replace_subscriptions, [{:room_a, "page"}], "test-user-id"}
      )

      wait_until(fn ->
        SubscriptionRegistry.bindings_of(instance_id) == %{{:room_a, "page"} => "test-user-id"}
      end)
    end

    test "redeems a handshake whose gossip arrives within the wait budget" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      handshake_id = "test-handshake-#{:erlang.unique_integer([:positive])}"

      conn =
        :get
        |> Plug.Test.conn("/?instance_id=#{instance_id}&handshake_id=#{handshake_id}")
        |> Plug.Test.init_test_session(%{hologram_session_id: session_id})

      pid = spawn(fn -> stream(conn, server_wait_ms: 200) end)

      Process.sleep(50)

      Handshake.insert(
        handshake_id,
        [],
        {instance_id, session_id, nil},
        System.system_time(:millisecond) + Handshake.stash_ttl_ms()
      )

      Process.sleep(50)

      assert Process.alive?(pid)

      Process.exit(pid, :kill)
    end

    test "blocks on receive after preparing the stream" do
      conn = conn_with_instance_id()
      pid = spawn(fn -> stream(conn) end)

      Process.sleep(50)

      assert Process.alive?(pid)

      Process.exit(pid, :kill)
    end

    test "ignores unknown messages without exiting" do
      conn = conn_with_instance_id()
      pid = spawn(fn -> stream(conn) end)

      Process.sleep(50)
      send(pid, :some_unknown_message)
      send(pid, {:another, "message"})
      Process.sleep(50)

      assert Process.alive?(pid)

      Process.exit(pid, :kill)
    end

    test "exits cleanly on {:close, reason}" do
      conn = conn_with_instance_id()
      pid = spawn(fn -> stream(conn) end)

      Process.sleep(50)
      send(pid, {:close, :superseded})
      Process.sleep(50)

      refute Process.alive?(pid)
    end

    test "configures the SSE process's max_heap_size flag" do
      conn = conn_with_instance_id()
      pid = spawn(fn -> stream(conn) end)
      Process.sleep(50)

      {:max_heap_size, settings} = Process.info(pid, :max_heap_size)
      assert settings.size == 1_000_000
      assert settings.kill == true
      assert settings.error_logger == true

      Process.exit(pid, :kill)
    end
  end

  describe "subscribe_to_announce_topics/1" do
    test "subscribes to all three identity-level announce topics for an authenticated connection" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"

      conn =
        %{hologram_session_id: session_id, hologram_user_id: user_id}
        |> conn_with_instance_id()
        |> subscribe_to_announce_topics()

      instance_id = conn.query_params["instance_id"]

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.instance_announce_topic(instance_id),
        :hi_instance
      )

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.session_announce_topic(session_id),
        :hi_session
      )

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.user_announce_topic(user_id),
        :hi_user
      )

      assert_receive :hi_instance
      assert_receive :hi_session
      assert_receive :hi_user
    end

    test "skips the user announce topic for an anonymous connection" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      %{hologram_session_id: session_id}
      |> conn_with_instance_id()
      |> subscribe_to_announce_topics()

      user_id = "any-user"

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.user_announce_topic(user_id),
        :hi_user
      )

      refute_receive :hi_user
    end

    test "does not subscribe to user-addressable identity topics" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"

      conn =
        %{hologram_session_id: session_id, hologram_user_id: user_id}
        |> conn_with_instance_id()
        |> subscribe_to_announce_topics()

      instance_id = conn.query_params["instance_id"]

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.identity_topic(:instance, instance_id),
        :hi_instance
      )

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.identity_topic(:session, session_id),
        :hi_session
      )

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        Realtime.identity_topic(:user, user_id),
        :hi_user
      )

      refute_receive :hi_instance
      refute_receive :hi_session
      refute_receive :hi_user
    end
  end
end
