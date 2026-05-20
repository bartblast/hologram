defmodule Hologram.Realtime.SSETest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.SSE

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.SubscriptionRegistry

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Handshake)
    start_supervised!({Handshake, boot_sync_timeout_ms: 0})

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

  describe "encode_envelope/2" do
    test "wraps an encoded action in the SSE event envelope" do
      action = %Action{name: :my_action, target: "c1"}
      {:ok, encoded} = Encoder.encode_term(action)

      assert encode_envelope(42, action) == "event: action\nid: 42\ndata: #{encoded}\n\n"
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

  describe "process_message/2" do
    test "writes an SSE comment line on :heartbeat" do
      conn = prepared_test_conn()
      send(self(), :heartbeat)

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body == ":\n\n"
    end

    test "schedules the next heartbeat after handling :heartbeat" do
      conn = prepared_test_conn()
      send(self(), :heartbeat)

      process_message(conn, 30)

      assert_receive :heartbeat
    end

    test "continues without writing on unknown messages" do
      conn = prepared_test_conn()
      send(self(), :some_unknown_message)

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body == ""
    end

    test "halts on {:close, reason}" do
      conn = prepared_test_conn()
      send(self(), {:close, :superseded})

      assert {:halt, ^conn} = process_message(conn)
    end

    test "dispatches a broadcast action as an SSE chunk when no identity matches the exclude list" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      action = %Action{name: :my_action, target: "c1"}
      send(self(), {:broadcast_action, action, []})

      {:cont, updated_conn} = process_message(conn)

      {:ok, encoded} = Encoder.encode_term(action)

      assert updated_conn.resp_body =~ "event: action\n"
      assert updated_conn.resp_body =~ "data: #{encoded}\n"
    end

    test "always dispatches when excluded_identities is empty even if conn has identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"

      conn =
        prepared_test_conn_with_identities(
          instance_id: instance_id,
          session_id: session_id,
          user_id: user_id
        )

      action = %Action{name: :my_action, target: "c1"}
      send(self(), {:broadcast_action, action, []})

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body =~ "event: action\n"
    end

    test "drops the broadcast when the conn's instance identity is in excluded_identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      action = %Action{name: :my_action, target: "c1"}
      send(self(), {:broadcast_action, action, [{:instance, instance_id}]})

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body == ""
    end

    test "drops the broadcast when the conn's session identity is in excluded_identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id, session_id: session_id)

      action = %Action{name: :my_action, target: "c1"}
      send(self(), {:broadcast_action, action, [{:session, session_id}]})

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body == ""
    end

    test "drops the broadcast when the conn's user identity is in excluded_identities" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id, user_id: user_id)

      action = %Action{name: :my_action, target: "c1"}
      send(self(), {:broadcast_action, action, [{:user, user_id}]})

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body == ""
    end

    test "dispatches when excluded_identities contains identities that don't match the conn" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = prepared_test_conn_with_identities(instance_id: instance_id)

      action = %Action{name: :my_action, target: "c1"}
      send(self(), {:broadcast_action, action, [{:instance, "other-instance"}]})

      {:cont, updated_conn} = process_message(conn)

      assert updated_conn.resp_body =~ "event: action\n"
    end

    test "subscribes to the channel's PubSub topic on {:sub, channel}" do
      conn = prepared_test_conn()
      send(self(), {:sub, :notifications})

      {:cont, _updated_conn} = process_message(conn)

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:notifications", :hello)

      assert_receive :hello
    end

    test "unsubscribes from the channel's PubSub topic on {:unsub, channel}" do
      conn = prepared_test_conn()
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram:channel:notifications")
      send(self(), {:unsub, :notifications})

      {:cont, _updated_conn} = process_message(conn)

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:notifications", :hello)

      refute_receive :hello
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

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:notifications", :hello_atom)
      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:room:lobby", :hello_tuple)

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

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:notifications", :hello)

      assert_receive :hello
      refute_receive :hello
    end

    test "creates a registry entry but does not subscribe when validated_bindings is empty" do
      instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"
      conn = conn_with_identities(instance_id: instance_id)

      attach_validated_subscriptions(conn, [])

      assert SubscriptionRegistry.bindings_of(instance_id) == %{}

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:notifications", :hello)

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

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram:channel:notifications", :hello)

      assert_receive :hello
    end
  end

  describe "subscribe_to_identity_channels/1" do
    test "subscribes to the instance channel" do
      conn = subscribe_to_identity_channels(conn_with_instance_id())
      instance_id = conn.query_params["instance_id"]
      instance_topic = "hologram:channel:instance:#{instance_id}"

      Phoenix.PubSub.broadcast(Hologram.PubSub, instance_topic, :hello)

      assert_receive :hello
    end

    test "subscribes to the session channel" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      %{hologram_session_id: session_id}
      |> conn_with_instance_id()
      |> subscribe_to_identity_channels()

      session_topic = "hologram:channel:session:#{session_id}"
      Phoenix.PubSub.broadcast(Hologram.PubSub, session_topic, :hello_session)

      assert_receive :hello_session
    end

    test "subscribes to the user channel when a user ID is present" do
      user_id = "test-user-#{:erlang.unique_integer([:positive])}"

      %{hologram_user_id: user_id}
      |> conn_with_instance_id()
      |> subscribe_to_identity_channels()

      user_topic = "hologram:channel:user:#{user_id}"
      Phoenix.PubSub.broadcast(Hologram.PubSub, user_topic, :hello_user)

      assert_receive :hello_user
    end

    test "does not subscribe to a user channel when no user ID is present" do
      subscribe_to_identity_channels(conn_with_instance_id())

      user_id = "test-user-#{:erlang.unique_integer([:positive])}"
      user_topic = "hologram:channel:user:#{user_id}"
      Phoenix.PubSub.broadcast(Hologram.PubSub, user_topic, :hello_user)

      refute_receive :hello_user
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
  end
end
