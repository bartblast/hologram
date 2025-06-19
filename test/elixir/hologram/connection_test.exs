defmodule Hologram.ConnectionTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Connection
  alias Hologram.Commons.SystemUtils

  @http_conn %Plug.Conn{
    method: "GET",
    path_info: ["hello", "world"],
    query_string: "",
    host: "localhost"
  }

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Hologram.Test.Fixtures.Socket.Channel.Module1)
  Code.ensure_loaded(Hologram.Test.Fixtures.Socket.Channel.Module6)

  describe "init/1" do
    test "returns {:ok, http_conn} tuple" do
      assert init(@http_conn) == {:ok, @http_conn}
    end
  end

  describe "handle_in/2, control messages" do
    test "responds with pong for ping message" do
      message = {"ping", [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, "pong"}, @http_conn}
    end
  end

  describe "handle_in/2, command" do
    test "next action is nil" do
      message =
        {~s'[2,{"d":["b0636f6d6d616e64",{"d":[["amodule","aElixir.Hologram.Test.Fixtures.Socket.Channel.Module1"],["aname","amy_command_a"],["aparams",{"d":[],"t":"m"}],["atarget","b06d795f7461726765745f31"]],"t":"m"}],"t":"l"}]',
         [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, ~s'Type.atom("nil")'}, @http_conn}
    end

    test "next action with target not specified" do
      message =
        {~s'[2,{"d":["b0636f6d6d616e64",{"d":[["amodule","aElixir.Hologram.Test.Fixtures.Socket.Channel.Module1"],["aname","amy_command_b"],["aparams",{"d":[["aa","i1"],["ab","i2"]],"t":"m"}],["atarget","b06d795f7461726765745f31"]],"t":"m"}],"t":"l"}]',
         [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok,
                {:text,
                 ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'},
                @http_conn}
    end

    test "next action with target specified" do
      message =
        {~s'[2,{"d":["b0636f6d6d616e64",{"d":[["amodule","aElixir.Hologram.Test.Fixtures.Socket.Channel.Module1"],["aname","amy_command_c"],["aparams",{"d":[["aa","i1"],["ab","i2"]],"t":"m"}],["atarget","b06d795f7461726765745f31"]],"t":"m"}],"t":"l"}]',
         [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok,
                {:text,
                 ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_2")]])'},
                @http_conn}
    end

    test "next action params contain an anonymous function that is not a named function capture" do
      message =
        {~s'[2,{"d":["b0636f6d6d616e64",{"d":[["amodule","aElixir.Hologram.Test.Fixtures.Socket.Channel.Module6"],["aname","amy_command_6"],["aparams",{"d":[],"t":"m"}],["atarget","b06d795f7461726765745f31"]],"t":"m"}],"t":"l"}]',
         [opcode: :text]}

      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains a function that is not a named function capture"
        else
          "term contains a function that is not a remote function capture"
        end

      assert handle_in(message, @http_conn) == {:reply, :error, {:text, expected_msg}, @http_conn}
    end
  end

  describe "handle_info/2" do
    test "returns {:ok, http_conn} tuple" do
      message = :dummy

      assert handle_info(message, @http_conn) == {:ok, @http_conn}
    end
  end
end
