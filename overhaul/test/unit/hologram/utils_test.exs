defmodule Hologram.UtilsTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Test.Fixtures.Utils.Module1
  alias Hologram.Utils

  test "append/2" do
    assert Utils.append("string", "suffix") == "stringsuffix"
  end

  describe "atomize_keys/1" do
    test "map" do
      map = %{"key_1" => 1, "key_2" => %{"key_3" => 3}, key_4: 4}
      expected = %{key_1: 1, key_2: %{key_3: 3}, key_4: 4}

      assert Utils.atomize_keys(map) == expected
    end

    test "list" do
      list = [%{"map_1" => 1}, %{"map_2" => 2}]
      expected = [%{map_1: 1}, %{map_2: 2}]

      assert Utils.atomize_keys(list) == expected
    end

    test "struct" do
      struct = %Module1{key_1: "value_1", key_2: "value_2"}
      assert Utils.atomize_keys(struct) == struct
    end

    test "nil" do
      assert Utils.atomize_keys(nil) == nil
    end

    test "integer" do
      assert Utils.atomize_keys(9) == 9
    end
  end

  test "keyword_to_map/1" do
    keyword = [a: 1, b: 2, a: 3]
    result = Utils.keyword_to_map(keyword)

    assert result == %{a: 3, b: 2}
  end

  test "prepend/2" do
    assert Utils.prepend("string", "prefix") == "prefixstring"
  end

  test "string_prepend/1" do
    result = Utils.string_prepend("abc", "xyz")
    assert result == "xyzabc"
  end
end
