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

  describe "put_cookie/4" do
    test "adds a cookie with default options" do
      result = Server.put_cookie(%Server{}, "my_cookie", "abc123")

      expected_cookie = %{
        value: "abc123",
        domain: nil,
        max_age: nil,
        path: nil,
        same_site: :lax,
        secure: true
      }

      assert result.cookies == %{"my_cookie" => expected_cookie}
    end

    test "adds a cookie with custom options" do
      opts = [
        domain: "example.com",
        max_age: 3_600,
        path: "/admin",
        same_site: :strict,
        secure: false
      ]

      result = Server.put_cookie(%Server{}, "my_cookie", "abc123", opts)

      expected_cookie = %{
        value: "abc123",
        domain: "example.com",
        max_age: 3_600,
        path: "/admin",
        same_site: :strict,
        secure: false
      }

      assert result.cookies == %{"my_cookie" => expected_cookie}
    end

    test "adds multiple cookies to existing server struct" do
      server = %Server{cookies: %{"existing" => %{value: "old"}}}

      result =
        server
        |> Server.put_cookie("first", "value_1")
        |> Server.put_cookie("second", "value_2")

      assert Map.has_key?(result.cookies, "existing")
      assert Map.has_key?(result.cookies, "first")
      assert Map.has_key?(result.cookies, "second")

      assert result.cookies["first"].value == "value_1"
      assert result.cookies["second"].value == "value_2"
    end

    test "overwrites existing cookie with same key" do
      server = %Server{cookies: %{"theme" => %{value: "light"}}}

      result = Server.put_cookie(server, "theme", "dark")

      assert result.cookies["theme"].value == "dark"
      assert map_size(result.cookies) == 1
    end

    test "supports different value types" do
      result =
        %Server{}
        |> Server.put_cookie("string", "text")
        |> Server.put_cookie("integer", 42)
        |> Server.put_cookie("boolean", true)
        |> Server.put_cookie("list", [1, 2, 3])

      assert result.cookies["string"].value == "text"
      assert result.cookies["integer"].value == 42
      assert result.cookies["boolean"].value == true
      assert result.cookies["list"].value == [1, 2, 3]
    end

    test "raises ArgumentError when key is not a string" do
      expected_msg = """
      Cookie key must be a string, but received :abc.

      Cookie keys must be strings according to web standards.
      Try converting your key to a string: "abc".\
      """

      assert_error ArgumentError, expected_msg, fn ->
        Server.put_cookie(%Server{}, :abc, "value")
      end
    end

    test "partial options override defaults" do
      result = Server.put_cookie(%Server{}, "my_cookie", "abc123", secure: false, path: "/app")

      expected_cookie = %{
        value: "abc123",
        domain: nil,
        max_age: nil,
        path: "/app",
        same_site: :lax,
        secure: false
      }

      assert result.cookies == %{"my_cookie" => expected_cookie}
    end
  end
end
