defmodule Hologram.Runtime.StaticDigestStoreTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime.StaticDigestStore

  @static_path Reflection.root_static_path()

  describe "get/1" do
    test "binary file_path" do
      StaticDigestStore.run(path: @static_path)

      file_path = "/test_dir_1/test_dir_2/test_file_1.css"
      result = StaticDigestStore.get(file_path)
      expected = {:ok, "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"}

      assert result == expected
    end

    test "atom file_path" do
      StaticDigestStore.run(path: @static_path)

      file_path = :"/test_dir_1/test_dir_2/test_file_1.css"
      result = StaticDigestStore.get(file_path)
      expected = {:ok, "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"}

      assert result == expected
    end
  end

  test "get_manifest/0", %{expected_store_content: expected_store_content} do
    StaticDigestStore.run(path: @static_path)
    assert StaticDigestStore.get_manifest() == expected_store_content.__manifest__
  end

  # TODO: test explicitely
  test "populate_table/1", %{expected_store_content: expected_store_content} do
    StaticDigestStore.run(path: @static_path)
    assert StaticDigestStore.get_all() == expected_store_content
  end
end
