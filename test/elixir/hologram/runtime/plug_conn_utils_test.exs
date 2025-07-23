defmodule Hologram.Runtime.PlugConnUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Cookie

  describe "extract_cookies/1" do
    test "extracts cookies from Plug.Conn struct with cookies" do
      conn = %Plug.Conn{
        cookies: %{"user_id" => "abc123", "theme" => "dark"},
        req_cookies: %{"user_id" => "abc123", "theme" => "dark"}
      }

      result = extract_cookies(conn)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "extracts cookies from Plug.Conn struct with no cookies" do
      conn = %Plug.Conn{cookies: %{}, req_cookies: %{}}

      result = extract_cookies(conn)

      assert result == %{}
    end

    test "fetches cookies if they haven't been fetched yet" do
      # This simulates a Plug.Conn struct that hasn't had fetch_cookies/1 called on it.
      # The actual cookies must be fetched from headers.
      conn = %Plug.Conn{
        cookies: %Plug.Conn.Unfetched{aspect: :cookies},
        req_cookies: %Plug.Conn.Unfetched{aspect: :cookies},
        req_headers: [
          {"cookie", "user_id=abc123; theme=dark"}
        ]
      }

      result = extract_cookies(conn)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "excludes hologram_session cookie" do
      conn = %Plug.Conn{
        cookies: %{
          "user_id" => "abc123",
          "theme" => "dark",
          "hologram_session" => "session_data_xyz789"
        },
        req_cookies: %{
          "user_id" => "abc123",
          "theme" => "dark",
          "hologram_session" => "session_data_xyz789"
        }
      }

      result = extract_cookies(conn)

      refute Map.has_key?(result, "hologram_session")
    end

    test "decodes cookie values using Cookie.decode/1" do
      encoded_map = Cookie.encode(%{key: "value"})

      conn = %Plug.Conn{
        cookies: %{
          "plain_cookie" => "plain_value",
          "encoded_cookie" => encoded_map
        },
        req_cookies: %{
          "plain_cookie" => "plain_value",
          "encoded_cookie" => encoded_map
        }
      }

      result = extract_cookies(conn)

      assert result["plain_cookie"] == "plain_value"
      assert result["encoded_cookie"] == %{key: "value"}
    end
  end

  describe "init_conn/1" do
    test "fetches cookies for the connection" do
      conn_fixture =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{})

      # This simulates a Plug.Conn struct that hasn't had fetch_cookies/1 called on it
      initial_conn = %{
        conn_fixture
        | cookies: %Plug.Conn.Unfetched{aspect: :cookies},
          req_cookies: %Plug.Conn.Unfetched{aspect: :cookies}
      }

      result = init_conn(initial_conn)

      assert Plug.Conn.get_cookies(result) == %{}
    end

    test "fetches session for the connection" do
      session_opts = [
        store: :cookie,
        key: "session_key",
        signing_salt: "abcdefgh",
        same_site: "Lax"
      ]

      session_config = Plug.Session.init(session_opts)

      initial_conn =
        :get
        |> Plug.Test.conn("/")
        # This simulates a Plug.Conn struct that hasn't had fetch_session/1 called on it
        |> Plug.Session.call(session_config)

      result = init_conn(initial_conn)

      assert Plug.Conn.get_session(result) == %{}
    end

    test "does not raise if cookies and session are already fetched" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Conn.fetch_cookies()
        |> Plug.Test.init_test_session(%{})

      result = init_conn(conn)

      assert Plug.Conn.get_cookies(result) == %{}
      assert Plug.Conn.get_session(result) == %{}
    end
  end
end
