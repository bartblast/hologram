defmodule Hologram.ApplicationTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Application
  import Hologram.Test.Stubs
  import Mox

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    original_hologram_start_flag = System.get_env("HOLOGRAM_START")

    setup_asset_path_registry(AssetPathRegistryStub, false)
    setup_asset_manifest_cache(AssetManifestCacheStub, false)

    setup_page_digest_registry(PageDigestRegistryStub, false)

    setup_page_module_resolver(PageModuleResolverStub, false)

    on_exit(fn ->
      if original_hologram_start_flag do
        System.put_env("HOLOGRAM_START", original_hologram_start_flag)
      else
        System.delete_env("HOLOGRAM_START")
      end
    end)
  end

  describe "start/2" do
    test "starts full supervisor when HOLOGRAM_START is set" do
      System.put_env("HOLOGRAM_START", "1")

      assert {:ok, pid} = start(:my_app, :temporary)
      assert is_pid(pid)

      children = Supervisor.which_children(pid)
      child_modules = Enum.map(children, fn {module, _pid, _type, _modules} -> module end)

      assert Hologram.Assets.PageDigestRegistry in child_modules
      assert Hologram.Assets.PathRegistry in child_modules
      assert Hologram.Assets.ManifestCache in child_modules
      assert Hologram.Router.PageModuleResolver in child_modules
    end

    test "starts empty supervisor when HOLOGRAM_START is not set" do
      System.delete_env("HOLOGRAM_START")

      assert {:ok, pid} = start(:my_app, :temporary)
      assert is_pid(pid)

      children = Supervisor.which_children(pid)
      assert children == []
    end
  end
end
