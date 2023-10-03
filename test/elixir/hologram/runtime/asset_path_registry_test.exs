defmodule Hologram.Runtime.AssetPathRegistryTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.AssetPathRegistry

  alias Hologram.Commons.ETS
  alias Hologram.Commons.Reflection

  @ets_table_name random_atom()
  @process_name random_atom()
  @static_path "#{Reflection.tmp_path()}/#{__MODULE__}"
  @opts [ets_table_name: @ets_table_name, process_name: @process_name, static_path: @static_path]

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
    assert {:ok, @ets_table_name} = init(@opts)
    assert ets_table_exists?(@ets_table_name)
    assert ETS.get_all(@ets_table_name) == mapping
  end

  describe "lookup/2" do
    setup do
      start_link(@opts)
      :ok
    end

    test "asset exists" do
      assert lookup("/test_dir_1/test_dir_2/test_file_1.css", @ets_table_name) ==
               {:ok, "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"}
    end

    test "asset doesn't exist" do
      assert lookup("/invalid_file.css", @ets_table_name) == :error
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link(@opts)
    assert is_pid(pid)
    assert process_name_registered?(@process_name)
    assert ets_table_exists?(@ets_table_name)
  end
end
