defmodule Hologram.ServerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Server

  alias Hologram.Server
  alias Hologram.Server.Cookie

  describe "put_cookie/4" do
    test "adds a cookie with default options" do
      result = put_cookie(%Server{}, "my_cookie", "abc123")

      expected_cookie = %Cookie{
        value: "abc123",
        domain: nil,
        http_only: true,
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
        http_only: false,
        max_age: 3_600,
        path: "/admin",
        same_site: :strict,
        secure: false
      ]

      result = put_cookie(%Server{}, "my_cookie", "abc123", opts)

      expected_cookie = %Cookie{
        value: "abc123",
        domain: "example.com",
        http_only: false,
        max_age: 3_600,
        path: "/admin",
        same_site: :strict,
        secure: false
      }

      assert result.cookies == %{"my_cookie" => expected_cookie}
    end

    test "adds multiple cookies to existing server struct" do
      server = %Server{cookies: %{"existing" => %Cookie{value: "old"}}}

      result =
        server
        |> put_cookie("first", "value_1")
        |> put_cookie("second", "value_2")

      assert Map.has_key?(result.cookies, "existing")
      assert Map.has_key?(result.cookies, "first")
      assert Map.has_key?(result.cookies, "second")

      assert result.cookies["first"].value == "value_1"
      assert result.cookies["second"].value == "value_2"
    end

    test "overwrites existing cookie with same key" do
      server = %Server{cookies: %{"theme" => %Cookie{value: "light"}}}

      result = put_cookie(server, "theme", "dark")

      assert result.cookies["theme"].value == "dark"
      assert map_size(result.cookies) == 1
    end

    test "supports different value types" do
      result =
        %Server{}
        |> put_cookie("string", "text")
        |> put_cookie("integer", 42)
        |> put_cookie("boolean", true)
        |> put_cookie("list", [1, 2, 3])

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
        put_cookie(%Server{}, :abc, "value")
      end
    end

    test "partial options override defaults" do
      result = put_cookie(%Server{}, "my_cookie", "abc123", secure: false, path: "/app")

      expected_cookie = %Cookie{
        value: "abc123",
        domain: nil,
        http_only: true,
        max_age: nil,
        path: "/app",
        same_site: :lax,
        secure: false
      }

      assert result.cookies == %{"my_cookie" => expected_cookie}
    end
  end
end
