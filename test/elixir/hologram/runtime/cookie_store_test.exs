defmodule Hologram.Runtime.CookieStoreTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.CookieStore

  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CookieStore

  describe "effective_cookies/1" do
    test "returns effective cookies with timestamp precedence" do
      store = %CookieStore{
        persisted: %{"key_1" => "value_1", "key_2" => {:put, 100, %Cookie{value: "old_value"}}},
        pending: %{
          "key_2" => {:put, 200, %Cookie{value: "new_value"}},
          "key_3" => {:delete, 150},
          "key_4" => {:put, 180, %Cookie{value: nil}}
        }
      }

      result = effective_cookies(store)

      assert result == %{"key_1" => "value_1", "key_2" => "new_value", "key_4" => nil}
    end

    test "returns only persisted cookies when no pending operations" do
      store = %CookieStore{
        persisted: %{"user_id" => "abc123", "theme" => "dark"},
        pending: %{}
      }

      result = effective_cookies(store)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "returns only pending cookies when no persisted cookies" do
      store = %CookieStore{
        persisted: %{},
        pending: %{
          "new_key" => {:put, 100, %Cookie{value: "new_value"}},
          "nil_key" => {:put, 200, %Cookie{value: nil}}
        }
      }

      result = effective_cookies(store)

      assert result == %{"new_key" => "new_value", "nil_key" => nil}
    end

    test "excludes deleted cookies" do
      store = %CookieStore{
        persisted: %{"to_delete" => "old_value", "to_keep" => "kept_value"},
        pending: %{
          "to_delete" => {:delete, 100},
          "also_deleted" => {:delete, 150}
        }
      }

      result = effective_cookies(store)

      assert result == %{"to_keep" => "kept_value"}
    end

    test "gives precedence to higher timestamps" do
      store = %CookieStore{
        persisted: %{"key" => {:put, 300, %Cookie{value: "newer_persisted"}}},
        pending: %{"key" => {:put, 200, %Cookie{value: "older_pending"}}}
      }

      result = effective_cookies(store)

      assert result == %{"key" => "newer_persisted"}
    end

    test "treats plain string values as timestamp 0" do
      store = %CookieStore{
        persisted: %{"key" => "plain_string"},
        pending: %{"key" => {:put, 1, %Cookie{value: "timestamped_value"}}}
      }

      result = effective_cookies(store)

      assert result == %{"key" => "timestamped_value"}
    end

    test "handles deletion overriding persisted values" do
      store = %CookieStore{
        persisted: %{"key" => "value_to_delete"},
        pending: %{"key" => {:delete, 100}}
      }

      result = effective_cookies(store)

      assert result == %{}
    end

    test "handles multiple operations on same key with different timestamps" do
      store = %CookieStore{
        persisted: %{"key" => {:put, 100, %Cookie{value: "first"}}},
        pending: %{"key" => {:put, 200, %Cookie{value: "second"}}}
      }

      result = effective_cookies(store)

      assert result == %{"key" => "second"}
    end

    test "returns empty map for empty store" do
      store = %CookieStore{persisted: %{}, pending: %{}}

      result = effective_cookies(store)

      assert result == %{}
    end

    test "includes nil values in result" do
      store = %CookieStore{
        persisted: %{},
        pending: %{
          "nil_cookie" => {:put, 100, %Cookie{value: nil}},
          "string_cookie" => {:put, 200, %Cookie{value: "value"}}
        }
      }

      result = effective_cookies(store)

      assert result == %{"nil_cookie" => nil, "string_cookie" => "value"}
    end

    test "handles complex scenario with mixed operations" do
      store = %CookieStore{
        persisted: %{
          "unchanged" => "persisted_value",
          "overridden" => {:put, 50, %Cookie{value: "old"}},
          "deleted_later" => "will_be_deleted"
        },
        pending: %{
          "overridden" => {:put, 100, %Cookie{value: "new"}},
          "deleted_later" => {:delete, 75},
          "new_cookie" => {:put, 125, %Cookie{value: "fresh"}},
          "deleted_immediately" => {:delete, 150}
        }
      }

      result = effective_cookies(store)

      assert result == %{
               "unchanged" => "persisted_value",
               "overridden" => "new",
               "new_cookie" => "fresh"
             }
    end
  end

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
