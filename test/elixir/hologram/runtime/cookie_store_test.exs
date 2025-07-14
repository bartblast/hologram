defmodule Hologram.Runtime.CookieStoreTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.CookieStore

  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CookieStore

  describe "effective_cookies/1" do
    test "gives precedence to higher timestamps, ops: put & put" do
      store = %CookieStore{
        persisted: %{"key" => {:put, 200, %Cookie{value: "old_value"}}},
        pending: %{"key" => {:put, 300, %Cookie{value: "new_value"}}}
      }

      result = effective_cookies(store)

      assert result == %{"key" => "new_value"}
    end

    test "gives precedence to higher timestamps, ops: put & delete" do
      store = %CookieStore{
        persisted: %{"key" => {:put, 200, %Cookie{value: "new_value"}}},
        pending: %{"key" => {:delete, 300}}
      }

      result = effective_cookies(store)

      assert result == %{}
    end

    test "gives precedence to higher timestamps, ops: delete & put" do
      store = %CookieStore{
        persisted: %{"key" => {:delete, 200}},
        pending: %{"key" => {:put, 300, %Cookie{value: "new_value"}}}
      }

      result = effective_cookies(store)

      assert result == %{"key" => "new_value"}
    end

    test "gives precedence to higher timestamps, ops: nop & put" do
      store = %CookieStore{
        persisted: %{"key" => {:nop, 0, "old_value"}},
        pending: %{"key" => {:put, 1, %Cookie{value: "new_value"}}}
      }

      result = effective_cookies(store)

      assert result == %{"key" => "new_value"}
    end

    test "gives precedence to higher timestamps, ops: nop & delete" do
      store = %CookieStore{
        persisted: %{"key" => {:nop, 0, "old_value"}},
        pending: %{"key" => {:delete, 1}}
      }

      result = effective_cookies(store)

      assert result == %{}
    end

    test "handles delete operations in both persisted and pending sets" do
      store = %CookieStore{
        persisted: %{"key" => {:delete, 200}},
        pending: %{"key" => {:delete, 300}}
      }

      result = effective_cookies(store)

      assert result == %{}
    end

    test "returns only persisted values when no pending operations" do
      store = %CookieStore{
        persisted: %{
          "user_id" => {:nop, 0, "abc123"},
          "theme" => {:put, 100, %Cookie{value: "dark"}}
        },
        pending: %{}
      }

      result = effective_cookies(store)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "returns only pending values when no persisted operations" do
      store = %CookieStore{
        persisted: %{},
        pending: %{
          "user_id" => {:put, 100, %Cookie{value: "abc123"}},
          "theme" => {:put, 200, %Cookie{value: "dark"}}
        }
      }

      result = effective_cookies(store)

      assert result == %{"user_id" => "abc123", "theme" => "dark"}
    end

    test "returns empty map for empty store" do
      store = %CookieStore{persisted: %{}, pending: %{}}

      result = effective_cookies(store)

      assert result == %{}
    end

    test "includes nil values from nop operations" do
      store = %CookieStore{
        persisted: %{"key" => {:nop, 0, nil}},
        pending: %{}
      }

      result = effective_cookies(store)

      assert result == %{"key" => nil}
    end

    test "includes nil values from put operations" do
      store = %CookieStore{
        persisted: %{"key" => {:put, 100, %Cookie{value: nil}}},
        pending: %{}
      }

      result = effective_cookies(store)

      assert result == %{"key" => nil}
    end

    test "handles complex scenario with mixed operations" do
      store = %CookieStore{
        persisted: %{
          "unchanged" => {:nop, 0, "persisted_value"},
          "overridden" => {:put, 50, %Cookie{value: "old_value"}},
          "deleted_later" => {:nop, 0, "will_be_deleted"}
        },
        pending: %{
          "overridden" => {:put, 100, %Cookie{value: "new_value"}},
          "deleted_later" => {:delete, 75},
          "new_cookie" => {:put, 125, %Cookie{value: "fresh"}},
          "deleted_immediately" => {:delete, 150}
        }
      }

      result = effective_cookies(store)

      assert result == %{
               "unchanged" => "persisted_value",
               "overridden" => "new_value",
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
               persisted: %{"user_id" => {:nop, 0, "abc123"}, "theme" => {:nop, 0, "dark"}},
               pending: %{}
             }
    end

    test "excludes hologram_session cookie from persisted cookies" do
      conn = %Plug.Conn{
        cookies: %{"user_id" => "abc123", "hologram_session" => "session_data_xyz789"},
        req_cookies: %{"user_id" => "abc123", "hologram_session" => "session_data_xyz789"}
      }

      result = from(conn)

      refute Map.has_key?(result.persisted, "hologram_session")
    end
  end

  describe "has_pending_ops?/1" do
    test "returns true when store has pending operations" do
      store = %CookieStore{
        persisted: %{},
        pending: %{"key" => {:put, 100, %Cookie{value: "value"}}}
      }

      assert has_pending_ops?(store)
    end

    test "returns false when store has no pending operations" do
      store = %CookieStore{
        persisted: %{"key" => {:nop, 0, "value"}},
        pending: %{}
      }

      refute has_pending_ops?(store)
    end
  end

  describe "merge_pending_ops/2" do
    test "merges operations with higher timestamps, ops: put & put" do
      store = %CookieStore{
        persisted: %{"key_1" => {:put, 100, %Cookie{value: "old_1"}}},
        pending: %{"key_2" => {:put, 200, %Cookie{value: "old_2"}}}
      }

      ops = %{
        "key_1" => {:put, 300, %Cookie{value: "new_1"}},
        "key_2" => {:put, 400, %Cookie{value: "new_2"}}
      }

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: ops}
    end

    test "merges operations with higher timestamps, ops: put & delete" do
      store = %CookieStore{
        persisted: %{"key_1" => {:put, 100, %Cookie{value: "old_1"}}},
        pending: %{"key_2" => {:put, 200, %Cookie{value: "old_2"}}}
      }

      ops = %{
        "key_1" => {:delete, 300},
        "key_2" => {:delete, 400}
      }

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: ops}
    end

    test "merges operations with higher timestamps, ops: delete & delete" do
      store = %CookieStore{
        persisted: %{"key_1" => {:delete, 100}},
        pending: %{"key_2" => {:delete, 200}}
      }

      ops = %{
        "key_1" => {:delete, 300},
        "key_2" => {:delete, 400}
      }

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: ops}
    end

    test "merges operations with higher timestamps, ops: delete & put" do
      store = %CookieStore{
        persisted: %{"key_1" => {:delete, 100}},
        pending: %{"key_2" => {:delete, 200}}
      }

      ops = %{
        "key_1" => {:put, 300, %Cookie{value: "new_1"}},
        "key_2" => {:put, 400, %Cookie{value: "new_2"}}
      }

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: ops}
    end

    test "merges operations with higher timestamps, ops: nop & put" do
      store = %CookieStore{
        persisted: %{"key_1" => {:nop, 0, "old_1"}},
        pending: %{"key_2" => {:nop, 0, "old_2"}}
      }

      ops = %{
        "key_1" => {:put, 300, %Cookie{value: "new_1"}},
        "key_2" => {:put, 400, %Cookie{value: "new_2"}}
      }

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: ops}
    end

    test "merges operations with higher timestamps, ops: nop & delete" do
      store = %CookieStore{
        persisted: %{"key_1" => {:nop, 0, "old_1"}},
        pending: %{"key_2" => {:nop, 0, "old_2"}}
      }

      ops = %{
        "key_1" => {:delete, 300},
        "key_2" => {:delete, 400}
      }

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: ops}
    end

    test "rejects operations with lower timestamps, ops: put & put" do
      store = %CookieStore{
        persisted: %{"key_1" => {:put, 100, %Cookie{value: "old_1"}}},
        pending: %{"key_2" => {:put, 200, %Cookie{value: "old_2"}}}
      }

      ops = %{
        "key_1" => {:put, 1, %Cookie{value: "new_1"}},
        "key_2" => {:put, 2, %Cookie{value: "new_2"}}
      }

      result = merge_pending_ops(store, ops)

      assert result == store
    end

    test "rejects operations with lower timestamps, ops: put & delete" do
      store = %CookieStore{
        persisted: %{"key_1" => {:put, 100, %Cookie{value: "old_1"}}},
        pending: %{"key_2" => {:put, 200, %Cookie{value: "old_2"}}}
      }

      ops = %{
        "key_1" => {:delete, 3},
        "key_2" => {:delete, 4}
      }

      result = merge_pending_ops(store, ops)

      assert result == store
    end

    test "rejects operations with lower timestamps, ops: delete & delete" do
      store = %CookieStore{
        persisted: %{"key_1" => {:delete, 100}},
        pending: %{"key_2" => {:delete, 200}}
      }

      ops = %{
        "key_1" => {:delete, 3},
        "key_2" => {:delete, 4}
      }

      result = merge_pending_ops(store, ops)

      assert result == store
    end

    test "rejects operations with lower timestamps, ops: delete & put" do
      store = %CookieStore{
        persisted: %{"key_1" => {:delete, 100}},
        pending: %{"key_2" => {:delete, 200}}
      }

      ops = %{
        "key_1" => {:put, 3, %Cookie{value: "new_1"}},
        "key_2" => {:put, 4, %Cookie{value: "new_2"}}
      }

      result = merge_pending_ops(store, ops)

      assert result == store
    end

    test "merges put operations for non-existent keys" do
      store = %CookieStore{persisted: %{}, pending: %{}}

      ops = %{"new_key" => {:put, 100, %Cookie{value: "value"}}}

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: %{"new_key" => {:put, 100, %Cookie{value: "value"}}}}
    end

    test "merges delete operations for non-existent keys" do
      store = %CookieStore{persisted: %{}, pending: %{}}

      ops = %{"new_key" => {:delete, 100}}

      result = merge_pending_ops(store, ops)

      assert result == %{store | pending: %{"new_key" => {:delete, 100}}}
    end
  end
end
