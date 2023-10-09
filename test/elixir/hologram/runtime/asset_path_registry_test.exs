defmodule Hologram.Runtime.AssetPathRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.AssetPathRegistry
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Runtime.AssetPathRegistry

  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    stub_with(AssetPathRegistryMock, AssetPathRegistryStub)

    static_dir_path = AssetPathRegistryStub.static_dir_path()
    clean_dir(static_dir_path)
    setup_asset_fixtures(static_dir_path)
  end

  test "get_mapping/0", %{mapping: mapping} do
    AssetPathRegistry.start_link([])
    assert get_mapping() == mapping
  end

  describe "handle_call/3" do
    test "get_mapping", %{mapping: mapping} do
      AssetPathRegistry.start_link([])
      process_name = AssetPathRegistryStub.process_name()

      assert GenServer.call(process_name, :get_mapping) == mapping
    end
  end

  test "init/1", %{mapping: mapping} do
    ets_table_name = AssetPathRegistryStub.ets_table_name()

    assert init(nil) == {:ok, nil}
    assert ets_table_exists?(ets_table_name)
    assert ETS.get_all(ets_table_name) == mapping
  end

  describe "lookup/2" do
    setup do
      AssetPathRegistry.start_link([])
      :ok
    end

    test "asset exists" do
      assert lookup("/test_dir_1/test_dir_2/test_file_1.css") ==
               {:ok, "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"}
    end

    test "asset doesn't exist" do
      assert lookup("/invalid_file.css") == :error
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = AssetPathRegistry.start_link([])
    assert is_pid(pid)
    assert process_name_registered?(AssetPathRegistryStub.process_name())
    assert ets_table_exists?(AssetPathRegistryStub.ets_table_name())
  end
end
