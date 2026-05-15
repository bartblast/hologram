defmodule Hologram.Realtime.SSETest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.SSE

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    :ok
  end

  defp conn_with_instance_id(session \\ %{}) do
    instance_id = "test-instance-#{:erlang.unique_integer([:positive])}"

    :get
    |> Plug.Test.conn("/?instance_id=#{instance_id}")
    |> Plug.Test.init_test_session(session)
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

      {:cont, updated_conn} = process_message(conn, 30_000)

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

      {:cont, updated_conn} = process_message(conn, 30_000)

      assert updated_conn.resp_body == ""
    end

    test "halts on {:close, reason}" do
      conn = prepared_test_conn()
      send(self(), {:close, :superseded})

      assert {:halt, ^conn} = process_message(conn, 30_000)
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

    test "subscribes to the session channel when a session ID is present" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"

      %{hologram_session_id: session_id}
      |> conn_with_instance_id()
      |> subscribe_to_identity_channels()

      session_topic = "hologram:channel:session:#{session_id}"
      Phoenix.PubSub.broadcast(Hologram.PubSub, session_topic, :hello_session)

      assert_receive :hello_session
    end

    test "does not subscribe to a session channel when no session ID is present" do
      subscribe_to_identity_channels(conn_with_instance_id())

      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      session_topic = "hologram:channel:session:#{session_id}"
      Phoenix.PubSub.broadcast(Hologram.PubSub, session_topic, :hello_session)

      refute_receive :hello_session
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
