defmodule Hologram.ConnectionTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Connection

  @http_conn %Plug.Conn{
    method: "GET",
    path_info: ["hello", "world"],
    query_string: "",
    host: "localhost"
  }

  describe "init/1" do
    test "returns {:ok, http_conn} tuple" do
      assert Connection.init(@http_conn) == {:ok, @http_conn}
    end
  end

  describe "handle_in/2" do
    test "responds with pong for ping message" do
      message = {"ping", [opcode: :text]}

      assert Connection.handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, "pong"}, @http_conn}
    end
  end

  describe "handle_info/2" do
    test "returns {:ok, http_conn} tuple" do
      message = :dummy

      assert Connection.handle_info(message, @http_conn) == {:ok, @http_conn}
    end
  end
end
