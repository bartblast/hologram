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

    # test "registers process with gproc using connection_id" do
    #   {:ok, state} = init(@plug_conn)

    #   process_name = {:hologram_connection, state.connection_id}

    #   # Verify the process is registered with the expected key (local registration in tests)
    #   assert :gproc.whereis_name({:n, :l, process_name}) == self()

    #   # Verify we can look up the process by connection_id
    #   registered_pids = :gproc.lookup_pids({:n, :l, process_name})
    #   assert registered_pids == [self()]
    # end
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
    test "returns {:ok, state} tuple for any message" do
      assert handle_info(:dummy, @state) == {:ok, @state}
    end

    test "no longer pushes live reload messages, which the SSE stream carries" do
      assert handle_info(:reload, @state) == {:ok, @state}

      assert handle_info({:compilation_error, [[%{tone: :banner, text: "boom"}]]}, @state) ==
               {:ok, @state}
    end
  end

  # describe "terminate/2" do
  #   test "returns :ok" do
  #     {:ok, state} = init(@plug_conn)

  #     assert terminate(:normal, state) == :ok
  #   end

  #   test "unregisters process from gproc" do
  #     {:ok, state} = init(@plug_conn)

  #     process_name = {:hologram_connection, state.connection_id}

  #     # Verify the process is registered before termination
  #     assert :gproc.whereis_name({:n, :l, process_name}) == self()

  #     terminate(:normal, state)

  #     # Verify the process is no longer registered after termination
  #     assert :gproc.whereis_name({:n, :l, process_name}) == :undefined
  #   end

  #   test "handles different termination reasons" do
  #     {:ok, state_1} = init(@plug_conn)
  #     assert terminate(:normal, state_1) == :ok

  #     {:ok, state_2} = init(@plug_conn)
  #     assert terminate(:shutdown, state_2) == :ok

  #     {:ok, state_3} = init(@plug_conn)
  #     assert terminate({:error, :some_error}, state_3) == :ok
  #   end
  # end
end
