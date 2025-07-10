defmodule Hologram.Runtime.CookieStoreTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.CookieStore
  alias Hologram.Runtime.CookieStore

  describe "from/1" do
    test "creates CookieStore struct from Plug.Conn struct" do
      conn = %Plug.Conn{
        cookies: %{"user_id" => "abc123", "theme" => "dark"},
        req_cookies: %{"user_id" => "abc123", "theme" => "dark"}
      }

      result = from(conn)

      assert result == %CookieStore{
               persisted: %{"user_id" => "abc123", "theme" => "dark"},
               pending: %{}
             }
    end

    test "excludes hologram_session cookie from persisted cookies" do
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

      result = from(conn)

      refute Map.has_key?(result.persisted, "hologram_session")
    end
  end
end
