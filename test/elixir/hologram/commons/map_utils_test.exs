defmodule Hologram.Commons.MapUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.MapUtils

  describe "diff/2" do
    test "returns empty list when both maps are empty" do
      assert diff(%{}, %{}) == []
    end

    test "returns empty list when maps are identical" do
      old_map = %{"session_id" => "abc123", "theme" => "dark"}
      new_map = %{"session_id" => "abc123", "theme" => "dark"}

      assert diff(old_map, new_map) == []
    end

    test "detects new entries" do
      old_map = %{"session_id" => "abc123"}
      new_map = %{"session_id" => "abc123", "theme" => "dark", "lang" => "en"}

      result = diff(old_map, new_map)

      assert length(result) == 2
      assert {"theme", "dark"} in result
      assert {"lang", "en"} in result
    end

    test "detects modified entries" do
      old_map = %{"session_id" => "abc123", "theme" => "dark"}
      new_map = %{"session_id" => "xyz789", "theme" => "light"}

      result = diff(old_map, new_map)

      assert length(result) == 2
      assert {"session_id", "xyz789"} in result
      assert {"theme", "light"} in result
    end

    test "detects deleted entries" do
      old_map = %{"session_id" => "abc123", "theme" => "dark", "lang" => "en"}
      new_map = %{"session_id" => "abc123"}

      result = diff(old_map, new_map)

      assert length(result) == 2
      assert {"theme", nil} in result
      assert {"lang", nil} in result
    end

    test "handles mixed scenario: new, modified, unchanged, and deleted entries" do
      old_map = %{
        # will be modified
        "session_id" => "abc123",
        # will remain unchanged
        "theme" => "dark",
        # will be deleted
        "lang" => "en",
        # will be deleted
        "timezone" => "UTC"
      }

      new_map = %{
        # modified
        "session_id" => "xyz789",
        # unchanged
        "theme" => "dark",
        # new
        "user_id" => "42",
        # new with complex value
        "preferences" => %{"sound" => true}
      }

      result = diff(old_map, new_map)

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

    test "handles empty old map (all new)" do
      old_map = %{}
      new_map = %{"session_id" => "abc123", "theme" => "dark"}

      result = diff(old_map, new_map)

      assert length(result) == 2
      assert {"session_id", "abc123"} in result
      assert {"theme", "dark"} in result
    end

    test "handles empty new map (all deleted)" do
      old_map = %{"session_id" => "abc123", "theme" => "dark"}
      new_map = %{}

      result = diff(old_map, new_map)

      assert length(result) == 2
      assert {"session_id", nil} in result
      assert {"theme", nil} in result
    end

    test "handles various value types correctly" do
      old_map = %{
        "string" => "old_value",
        "integer" => 42,
        "boolean" => true,
        "map" => %{"nested" => "old"},
        "list" => [1, 2, 3]
      }

      new_map = %{
        "string" => "new_value",
        "integer" => 100,
        "boolean" => false,
        "map" => %{"nested" => "new"},
        "list" => [4, 5, 6]
      }

      result = diff(old_map, new_map)

      assert length(result) == 5
      assert {"string", "new_value"} in result
      assert {"integer", 100} in result
      assert {"boolean", false} in result
      assert {"map", %{"nested" => "new"}} in result
      assert {"list", [4, 5, 6]} in result
    end

    test "handles setting existing entries to nil" do
      old_map = %{"to_clear" => "some_value", "keep" => "value"}
      new_map = %{"to_clear" => nil, "keep" => "value"}

      result = diff(old_map, new_map)

      assert result == [{"to_clear", nil}]
    end
  end
end
