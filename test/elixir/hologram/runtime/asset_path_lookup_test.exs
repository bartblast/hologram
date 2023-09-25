defmodule Hologram.Runtime.AssetPathLookupTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.AssetPathLookup

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection

  @static_path "#{Reflection.tmp_path()}/#{__MODULE__}"
  @store_key random_atom()
  @opts [static_path: @static_path, store_key: @store_key]

  setup do
    dir_2_path = @static_path <> "/test_dir_1/test_dir_2"
    file_1_path = dir_2_path <> "/test_file_1-11111111111111111111111111111111.css"
    file_2_path = dir_2_path <> "/test_file_2-22222222222222222222222222222222.css"
    file_3_path = dir_2_path <> "/page-33333333333333333333333333333333.js"

    dir_3_path = @static_path <> "/test_dir_3"
    file_4_path = dir_3_path <> "/test_file_4-44444444444444444444444444444444.css"
    file_5_path = dir_3_path <> "/test_file_5-55555555555555555555555555555555.css"
    file_6_path = dir_3_path <> "/page-66666666666666666666666666666666.js"

    dir_4_path = @static_path <> "/hologram"
    file_7_path = dir_4_path <> "/page-77777777777777777777777777777777.js"
    file_8_path = dir_4_path <> "/page-88888888888888888888888888888888.js"
    file_9_path = dir_4_path <> "/test_file_9-99999999999999999999999999999999.css"

    File.mkdir_p!(dir_2_path)
    File.mkdir_p!(dir_3_path)
    File.mkdir_p!(dir_4_path)

    [
      file_1_path,
      file_2_path,
      file_3_path,
      file_4_path,
      file_5_path,
      file_6_path,
      file_7_path,
      file_8_path,
      file_9_path
    ]
    |> Enum.each(&File.write!(&1, ""))

    :ok
  end

  test "init/1" do
    assert {:ok, %PLT{table_name: @store_key} = plt} = init(@opts)

    assert ets_table_exists?(@store_key)

    assert PLT.get_all(plt) == %{
             "/test_dir_1/test_dir_2/test_file_1.css" =>
               "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
             "/test_dir_1/test_dir_2/test_file_2.css" =>
               "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
             "/test_dir_1/test_dir_2/page.js" =>
               "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
             "/test_dir_3/test_file_4.css" =>
               "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
             "/test_dir_3/test_file_5.css" =>
               "/test_dir_3/test_file_5-55555555555555555555555555555555.css",
             "/test_dir_3/page.js" => "/test_dir_3/page-66666666666666666666666666666666.js",
             "/hologram/test_file_9.css" =>
               "/hologram/test_file_9-99999999999999999999999999999999.css"
           }
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link(@opts)
    assert is_pid(pid)
    assert ets_table_exists?(@store_key)
  end
end
