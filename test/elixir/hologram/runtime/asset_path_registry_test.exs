defmodule Hologram.Runtime.AssetPathRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.AssetPathRegistry
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.AssetPathRegistry

  defmodule Stub do
    @behaviour AssetPathRegistry

    def static_dir_path, do: "#{Reflection.tmp_path()}/#{__MODULE__}"

    def ets_table_name, do: __MODULE__

    def process_name, do: __MODULE__
  end

  setup :set_mox_global

  setup do
    stub_with(AssetPathRegistry.Mock, Stub)

    clean_dir(Stub.static_dir_path())
    setup_asset_fixtures(Stub.static_dir_path())
  end

  test "get_mapping/0", %{mapping: mapping} do
    AssetPathRegistry.start_link([])
    assert AssetPathRegistry.get_mapping() == mapping
  end

  test "init/1" do
    ets_table_name = Stub.ets_table_name()

    assert {:ok, nil} = init(nil)
    assert ets_table_exists?(ets_table_name)
    assert ETS.get_all(ets_table_name) == AssetPathRegistry.get_mapping()
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
    assert process_name_registered?(Stub.process_name())
    assert ets_table_exists?(Stub.ets_table_name())
  end
end
