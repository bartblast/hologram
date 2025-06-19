defmodule Hologram.ServerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Server
  alias Hologram.Server

  @http_conn %Plug.Conn{
    method: "GET",
    path_info: ["hello", "world"],
    query_string: "",
    host: "localhost"
  }

  describe "diff_cookies/2" do
    test "returns empty list when both maps are empty" do
      assert diff_cookies(%{}, %{}) == []
    end

    test "returns empty list when maps are identical" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark"}
      new_cookies = %{"session_id" => "abc123", "theme" => "dark"}

      assert diff_cookies(old_cookies, new_cookies) == []
    end

    test "detects new cookies" do
      old_cookies = %{"session_id" => "abc123"}
      new_cookies = %{"session_id" => "abc123", "theme" => "dark", "lang" => "en"}

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"theme", "dark"} in result
      assert {"lang", "en"} in result
    end

    test "detects modified cookies" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark"}
      new_cookies = %{"session_id" => "xyz789", "theme" => "light"}

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"session_id", "xyz789"} in result
      assert {"theme", "light"} in result
    end

    test "detects deleted cookies" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark", "lang" => "en"}
      new_cookies = %{"session_id" => "abc123"}

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"theme", nil} in result
      assert {"lang", nil} in result
    end

    test "handles mixed scenario: new, modified, unchanged, and deleted cookies" do
      old_cookies = %{
        # will be modified
        "session_id" => "abc123",
        # will remain unchanged
        "theme" => "dark",
        # will be deleted
        "lang" => "en",
        # will be deleted
        "timezone" => "UTC"
      }

      new_cookies = %{
        # modified
        "session_id" => "xyz789",
        # unchanged
        "theme" => "dark",
        # new
        "user_id" => "42",
        # new with complex value
        "preferences" => %{"sound" => true}
      }

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 5

      # Modified
      assert {"session_id", "xyz789"} in result

      # New
      assert {"user_id", "42"} in result
      assert {"preferences", %{"sound" => true}} in result

      # Deleted
      assert {"lang", nil} in result
      assert {"timezone", nil} in result

      # Unchanged should not be present
      refute {"theme", "dark"} in result
    end

    test "handles empty old cookies (all new)" do
      old_cookies = %{}
      new_cookies = %{"session_id" => "abc123", "theme" => "dark"}

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"session_id", "abc123"} in result
      assert {"theme", "dark"} in result
    end

    test "handles empty new cookies (all deleted)" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark"}
      new_cookies = %{}

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"session_id", nil} in result
      assert {"theme", nil} in result
    end

    test "handles various value types correctly" do
      old_cookies = %{
        "string" => "old_value",
        "integer" => 42,
        "boolean" => true,
        "map" => %{"nested" => "old"},
        "list" => [1, 2, 3]
      }

      new_cookies = %{
        "string" => "new_value",
        "integer" => 100,
        "boolean" => false,
        "map" => %{"nested" => "new"},
        "list" => [4, 5, 6]
      }

      result = diff_cookies(old_cookies, new_cookies)

      assert length(result) == 5
      assert {"string", "new_value"} in result
      assert {"integer", 100} in result
      assert {"boolean", false} in result
      assert {"map", %{"nested" => "new"}} in result
      assert {"list", [4, 5, 6]} in result
    end

    test "handles setting existing cookies to nil" do
      old_cookies = %{"to_clear" => "some_value", "keep" => "value"}
      new_cookies = %{"to_clear" => nil, "keep" => "value"}

      result = diff_cookies(old_cookies, new_cookies)

      assert result == [{"to_clear", nil}]
    end
  end

  describe "init/1" do
    test "returns {:ok, http_conn} tuple" do
      assert init(@http_conn) == {:ok, @http_conn}
    end
  end

  describe "handle_in/2" do
    test "responds with pong for ping message" do
      message = {"ping", [opcode: :text]}

      assert handle_in(message, @http_conn) ==
               {:reply, :ok, {:text, "pong"}, @http_conn}
    end
  end

  describe "handle_info/2" do
    test "returns {:ok, http_conn} tuple" do
      message = :dummy

      assert handle_info(message, @http_conn) == {:ok, @http_conn}
    end
  end

  describe "put_cookie/4" do
    test "adds a cookie with default options" do
      result = put_cookie(%Server{}, "my_cookie", "abc123")

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

      result = put_cookie(%Server{}, "my_cookie", "abc123", opts)

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
        |> put_cookie("first", "value_1")
        |> put_cookie("second", "value_2")

      assert Map.has_key?(result.cookies, "existing")
      assert Map.has_key?(result.cookies, "first")
      assert Map.has_key?(result.cookies, "second")

      assert result.cookies["first"].value == "value_1"
      assert result.cookies["second"].value == "value_2"
    end

    test "overwrites existing cookie with same key" do
      server = %Server{cookies: %{"theme" => %{value: "light"}}}

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
