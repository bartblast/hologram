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

  test "deserialize/1" do
    data = %{
      key_2: 2,
      key_1: {1, 3},
      key_3: %{
        b: 22,
        a: 11
      }
    }

    serialized = :erlang.term_to_binary(data, compressed: 9)
    result = Utils.deserialize(serialized)

    assert result == data
  end

  test "list_files_recursively/1" do
    result = Utils.list_files_recursively("test/unit/fixtures/utils/list_files_recursively")

    expected = [
      "test/unit/fixtures/utils/list_files_recursively/dir_1/dir_3/file_5.txt",
      "test/unit/fixtures/utils/list_files_recursively/dir_1/dir_3/file_6.txt",
      "test/unit/fixtures/utils/list_files_recursively/dir_1/file_3.txt",
      "test/unit/fixtures/utils/list_files_recursively/dir_1/file_4.txt",
      "test/unit/fixtures/utils/list_files_recursively/dir_2/file_7.txt",
      "test/unit/fixtures/utils/list_files_recursively/dir_2/file_8.txt",
      "test/unit/fixtures/utils/list_files_recursively/file_1.text",
      "test/unit/fixtures/utils/list_files_recursively/file_2.text"
    ]

    assert result == expected
  end

  test "prepend/2" do
    assert Utils.prepend("string", "prefix") == "prefixstring"
  end

  test "serialize/1" do
    data_1 = %{
      key_2: 2,
      key_1: {1, 3},
      key_3: %{
        b: 22,
        a: 11
      }
    }

    data_2 = %{
      key_3: %{
        a: 11,
        b: 22
      },
      key_1: {1, 3},
      key_2: 2
    }

    result_1 = Utils.serialize(data_1)
    result_2 = Utils.serialize(data_2)

    assert result_1 == result_2
    assert byte_size(result_1) == 53

    assert :erlang.binary_to_term(result_1) == data_1
    assert :erlang.binary_to_term(result_2) == data_2
  end

  test "string_prepend/1" do
    result = Utils.string_prepend("abc", "xyz")
    assert result == "xyzabc"
  end
end
