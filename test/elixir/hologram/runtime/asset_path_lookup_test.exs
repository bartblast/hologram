defmodule Hologram.Runtime.AssetPathLookupTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.AssetPathLookup

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection

  @process_name random_atom()
  @static_path "#{Reflection.tmp_path()}/#{__MODULE__}"
  @store_key random_atom()
  @opts [process_name: @process_name, static_path: @static_path, store_key: @store_key]

  setup do
    clean_dir(@static_path)
    setup_asset_fixtures(@static_path)
  end

  describe "handle_call/3" do
    test "get_mapping", %{mapping: mapping} do
      start_link(@opts)

      assert GenServer.call(@process_name, :get_mapping) == mapping
    end
  end

  test "init/1", %{mapping: mapping} do
    assert {:ok, %PLT{table_name: @store_key} = plt} = init(@opts)
    assert ets_table_exists?(@store_key)
    assert PLT.get_all(plt) == mapping
  end

  describe "lookup/2" do
    setup do
      start_link(@opts)
      :ok
    end

    test "asset exists" do
      assert lookup(@store_key, "/test_dir_1/test_dir_2/test_file_1.css") ==
               "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"
    end

    test "asset doesn't exist" do
      assert_raise KeyError, ~s(key "/invalid_file.css" not found in the PLT), fn ->
        lookup(@store_key, "/invalid_file.css")
      end
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link(@opts)
    assert is_pid(pid)
    assert process_name_registered?(@process_name)
    assert ets_table_exists?(@store_key)
  end
end
