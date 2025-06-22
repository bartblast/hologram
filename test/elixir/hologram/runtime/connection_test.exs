defmodule Hologram.Runtime.ConnectionTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Connection
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module1

  @http_conn %Plug.Conn{
    method: "GET",
    path_info: ["hello", "world"],
    query_string: "",
    host: "localhost"
  }

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Module1)

  describe "init/1" do
    test "returns {:ok, http_conn} tuple" do
      assert init(@http_conn) == {:ok, @http_conn}
    end
  end

  describe "handle_in/2" do
    test "handles messages with type only" do
      message = {~s'"ping"', [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, ~s'"pong"'}, @http_conn}
    end

    # Not needed (yet)
    # test "handles messages with type and payload"

    test "handles messages with type, payload and correlation ID" do
      message =
        {~s'["command",[2,{"d":[["amodule","aElixir.Hologram.Test.Fixtures.Runtime.MessageHandler.Module1"],["aname","amy_command_a"],["aparams",{"d":[],"t":"m"}],["atarget","b06d795f7461726765745f31"]],"t":"m"}],123]',
         [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, ~s'["reply",[1,"Type.atom(\\"nil\\")"],123]'}, @http_conn}
    end
  end

  describe "handle_info/2" do
    test "returns {:ok, http_conn} tuple" do
      message = :dummy

      assert handle_info(message, @http_conn) == {:ok, @http_conn}
    end
  end
end
