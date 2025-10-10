defmodule Hologram.Runtime.ConnectionTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.Connection
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Runtime.Connection.Module2

  use_module_stub :page_digest_registry

  setup :set_mox_global

  @plug_conn %Plug.Conn{
    host: "localhost",
    method: "GET",
    path_info: ["hello", "world"],
    req_headers: [{"cookie", "user_id=abc123; hologram_session=xyz789"}],
    query_string: ""
  }

  @state %{
    plug_conn: @plug_conn
  }

  describe "init/1" do
    test "returns {:ok, state} tuple with plug_conn and connection_id" do
      {:ok, state} = init(@plug_conn)

      assert %{connection_id: connection_id, plug_conn: plug_conn} = state

      assert plug_conn == @plug_conn
      assert is_binary(connection_id)

      assert String.match?(
               connection_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
             )
    end
  end

  describe "init/1 environment-dependent behavior" do
    setup do
      original_env = System.get_env("HOLOGRAM_ENV")

      on_exit(fn ->
        if original_env do
          System.put_env("HOLOGRAM_ENV", original_env)
        else
          System.delete_env("HOLOGRAM_ENV")
        end
      end)

      wait_for_process_cleanup(Hologram.PubSub)
      start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

      :ok
    end

    test "subscribes to hologram_live_reload topic when env is dev" do
      System.put_env("HOLOGRAM_ENV", "dev")

      init(@plug_conn)

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", :test_message)

      assert_receive :test_message
    end

    test "does not subscribe to hologram_live_reload topic when env is not dev" do
      System.put_env("HOLOGRAM_ENV", "test")

      init(@plug_conn)

      Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", :test_message)

      refute_receive :test_message, 100
    end
  end

  describe "handle_in/2" do
    test "handles page_bundle_path message" do
      setup_page_digest_registry(PageDigestRegistryStub)

      test_digest = "12345678901234567890123456789012"
      correlation_id = "test-correlation-123"

      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module2,
        test_digest
      )

      # Message format: ["page_bundle_path", payload, correlation_id]
      # Payload format: [serialization_protocol_version, serialized_data]
      serialized_module = "aElixir.Hologram.Test.Fixtures.Runtime.Connection.Module2"
      payload = [2, serialized_module]
      message = ["page_bundle_path", payload, correlation_id]
      encoded_message = Jason.encode!(message)

      # Expected response format: ["reply", page_bundle_path, correlation_id]
      expected_page_bundle_path = "/hologram/page-#{test_digest}.js"
      expected_response_data = ["reply", expected_page_bundle_path, correlation_id]
      expected_response = Jason.encode!(expected_response_data)

      assert handle_in({encoded_message, [opcode: :text]}, @state) ==
               {:reply, :ok, {:text, expected_response}, @state}
    end

    test "handles ping message" do
      message = {~s'"ping"', [opcode: :text]}

      assert handle_in(message, @state) ==
               {:reply, :ok, {:text, ~s'"pong"'}, @state}
    end
  end

  describe "handle_info/2" do
    test "handles :reload message" do
      message = :reload

      assert handle_info(message, @state) ==
               {:push, {:text, ~s'"reload"'}, @state}
    end

    test "handles {:compilation_error, output} message" do
      output = "Compile error in module MyModule"
      message = {:compilation_error, output}

      assert handle_info(message, @state) ==
               {:push, {:text, ~s'["compilation_error","Compile error in module MyModule"]'},
                @state}
    end

    test "returns {:ok, state} tuple for other messages" do
      message = :dummy

      assert handle_info(message, @state) == {:ok, @state}
    end
  end
end
