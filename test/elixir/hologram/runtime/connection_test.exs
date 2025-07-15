defmodule Hologram.Runtime.ConnectionTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Runtime.Connection

  alias Hologram.Runtime.CookieStore
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module1

  @plug_conn %Plug.Conn{
    host: "localhost",
    method: "GET",
    path_info: ["hello", "world"],
    req_headers: [{"cookie", "user_id=abc123; hologram_session=xyz789"}],
    query_string: ""
  }

  @state %{
    cookie_store: CookieStore.from(@plug_conn),
    plug_conn: @plug_conn
  }

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Module1)

  describe "init/1" do
    test "returns {:ok, state} tuple with cookie_store, plug_conn, and connection_id" do
      {:ok, state} = init(@plug_conn)

      assert %{
               connection_id: connection_id,
               cookie_store: cookie_store,
               plug_conn: plug_conn
             } = state

      assert cookie_store == CookieStore.from(@plug_conn)
      assert plug_conn == @plug_conn
      assert is_binary(connection_id)

      assert String.match?(
               connection_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
             )
    end

    test "registers process with gproc using connection_id" do
      {:ok, state} = init(@plug_conn)

      process_name = {:hologram_connection, state.connection_id}

      # Verify the process is registered with the expected key (local registration in tests)
      assert :gproc.whereis_name({:n, :l, process_name}) == self()

      # Verify we can look up the process by connection_id
      registered_pids = :gproc.lookup_pids({:n, :l, process_name})
      assert registered_pids == [self()]
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
    test "handles messages with type only" do
      message = {~s'"ping"', [opcode: :text]}

      assert handle_in(message, @state) ==
               {:reply, :ok, {:text, ~s'"pong"'}, @state}
    end

    # Not needed (yet)
    # test "handles messages with type and payload"

    test "handles messages with type, payload and correlation ID" do
      message =
        {~s'["command",[2,{"d":[["amodule","aElixir.Hologram.Test.Fixtures.Runtime.MessageHandler.Module1"],["aname","amy_command_a"],["aparams",{"d":[],"t":"m"}],["atarget","b06d795f7461726765745f31"]],"t":"m"}],123]',
         [opcode: :text]}

      assert handle_in(message, @state) ==
               {:reply, :ok, {:text, ~s'["reply",[1,"Type.atom(\\"nil\\")",0],123]'}, @state}
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
