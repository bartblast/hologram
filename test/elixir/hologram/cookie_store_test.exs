defmodule Hologram.CookieStoreTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.CookieStore

  describe "diff/2" do
    test "returns empty list when both maps are empty" do
      assert CookieStore.diff(%{}, %{}) == []
    end

    test "returns empty list when maps are identical" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark"}
      new_cookies = %{"session_id" => "abc123", "theme" => "dark"}

      assert CookieStore.diff(old_cookies, new_cookies) == []
    end

    test "detects new cookies" do
      old_cookies = %{"session_id" => "abc123"}
      new_cookies = %{"session_id" => "abc123", "theme" => "dark", "lang" => "en"}

      result = CookieStore.diff(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"theme", "dark"} in result
      assert {"lang", "en"} in result
    end

    test "detects modified cookies" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark"}
      new_cookies = %{"session_id" => "xyz789", "theme" => "light"}

      result = CookieStore.diff(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"session_id", "xyz789"} in result
      assert {"theme", "light"} in result
    end

    test "detects deleted cookies" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark", "lang" => "en"}
      new_cookies = %{"session_id" => "abc123"}

      result = CookieStore.diff(old_cookies, new_cookies)

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

      result = CookieStore.diff(old_cookies, new_cookies)

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

      result = CookieStore.diff(old_cookies, new_cookies)

      assert length(result) == 2
      assert {"session_id", "abc123"} in result
      assert {"theme", "dark"} in result
    end

    test "handles empty new cookies (all deleted)" do
      old_cookies = %{"session_id" => "abc123", "theme" => "dark"}
      new_cookies = %{}

      result = CookieStore.diff(old_cookies, new_cookies)

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

      result = CookieStore.diff(old_cookies, new_cookies)

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

      result = CookieStore.diff(old_cookies, new_cookies)

      assert result == [{"to_clear", nil}]
    end
  end
end
