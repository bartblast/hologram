defmodule Hologram.ServerTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Server

  @http_conn %Plug.Conn{
    method: "GET",
    path_info: ["hello", "world"],
    query_string: "",
    host: "localhost"
  }

  describe "init/1" do
    test "returns {:ok, http_conn} tuple" do
      assert Server.init(@http_conn) == {:ok, @http_conn}
    end
  end

  describe "handle_in/2" do
    test "responds with pong for ping message" do
      message = {"ping", [opcode: :text]}

      assert Server.handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, "pong"}, @http_conn}
    end
  end

  describe "handle_info/2" do
    test "returns {:ok, http_conn} tuple" do
      message = :dummy

      assert Server.handle_info(message, @http_conn) == {:ok, @http_conn}
    end
  end
end
