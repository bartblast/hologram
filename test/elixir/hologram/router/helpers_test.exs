defmodule Hologram.Router.HelpersTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router.Helpers
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Runtime.AssetPathRegistry

  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    stub_with(AssetPathRegistryMock, AssetPathRegistryStub)
    setup_asset_fixtures(AssetPathRegistryStub.static_dir_path())
  end

  describe "asset_path/1" do
    setup do
      AssetPathRegistry.start_link([])
      :ok
    end

    test "asset exists" do
      assert asset_path("test_dir_1/test_dir_2/test_file_1.css") ==
               "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css"
    end

    test "asset doesn't exist" do
      assert asset_path("invalid_file.css") == "/invalid_file.css"
    end
  end
end
