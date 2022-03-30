defmodule Hologram.Runtime.StaticDigestStoreTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime.StaticDigestStore

  setup do
    static_path = Reflection.release_static_path()

    dir_2_path = static_path <> "/test_dir_1/test_dir_2"
    file_1_path = dir_2_path <> "/test_file_1-11111111111111111111111111111111.css"
    file_2_path = dir_2_path <> "/test_file_2-22222222222222222222222222222222.css"
    file_3_path = dir_2_path <> "/page-33333333333333333333333333333333.js"

    dir_3_path = static_path <> "/test_dir_3"
    file_4_path = dir_3_path <> "/test_file_4-44444444444444444444444444444444.css"
    file_5_path = dir_3_path <> "/test_file_5-55555555555555555555555555555555.css"
    file_6_path = dir_3_path <> "/page-66666666666666666666666666666666.js"

    dir_4_path = static_path <> "/hologram"
    file_7_path = dir_4_path <> "/page-77777777777777777777777777777777.js"
    file_8_path = dir_4_path <> "/page-88888888888888888888888888888888.js"
    file_9_path = dir_4_path <> "/test_file_9-99999999999999999999999999999999.css"

    File.mkdir_p!(dir_2_path)
    File.mkdir_p!(dir_3_path)

    [file_1_path, file_2_path, file_3_path, file_4_path, file_5_path, file_6_path, file_7_path, file_8_path, file_9_path]
    |> Enum.each(&File.write!(&1, ""))

    expected_store_content_without_manifest = %{
      "/test_dir_1/test_dir_2/test_file_1.css": "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
      "/test_dir_1/test_dir_2/test_file_2.css": "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
      "/test_dir_1/test_dir_2/page.js": "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
      "/test_dir_3/test_file_4.css": "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
      "/test_dir_3/test_file_5.css": "/test_dir_3/test_file_5-55555555555555555555555555555555.css",
      "/test_dir_3/page.js": "/test_dir_3/page-66666666666666666666666666666666.js",
      "/hologram/test_file_9.css": "/hologram/test_file_9-99999999999999999999999999999999.css"
    }

    expected_store_content =
      %{
        __manifest__: "window.__hologramStaticDigestStore__ = #{Jason.encode!(expected_store_content_without_manifest)};"
      }
      |> Map.merge(expected_store_content_without_manifest)

    [
      expected_store_content: expected_store_content
    ]
  end

  test "populate_table/0", %{expected_store_content: expected_store_content} do
    StaticDigestStore.run()
    assert StaticDigestStore.get_all() == expected_store_content
  end

  test "get_manifest/0", %{expected_store_content: expected_store_content} do
    StaticDigestStore.run()
    assert StaticDigestStore.get_manifest() == expected_store_content.__manifest__
  end
end
