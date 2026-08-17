defmodule Hologram.ApplicationTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Application
  import Hologram.Test.Stubs
  import Mox

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver
  use_module_stub :sync_page_windows
  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    original_hologram_start_flag = System.get_env("HOLOGRAM_START")

    setup_asset_path_registry(AssetPathRegistryStub, false)
    setup_asset_manifest_cache(AssetManifestCacheStub, false)

    setup_page_digest_registry(PageDigestRegistryStub, false)

    setup_page_module_resolver(PageModuleResolverStub, false)

    setup_sync_page_windows(SyncPageWindowsStub, false)

    setup_query_cache(QueryCacheStub, false)

    # The supervisor-started cache populates from its own process, outside the
    # test's sandboxed connection - an empty sweep keeps it off the database.
    stub(QueryCacheMock, :component_modules, fn -> [] end)

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

      # The entity fixture modules activate the database unit (test env declares entities).
      # Inside it, the database child yields to the suite-wide gateway instance (database
      # singleton semantics), so nothing here disturbs concurrent database tests.
      assert Hologram.DB.Supervisor in child_modules

      assert Hologram.Assets.PageDigestRegistry in child_modules
      assert Hologram.Assets.PathRegistry in child_modules
      assert Hologram.Assets.ManifestCache in child_modules
      assert Hologram.Realtime.SubscriptionRegistry in child_modules
      assert Hologram.Router.PageModuleResolver in child_modules
      assert Hologram.Sync.PageWindows in child_modules

      # Stop the app tree deterministically - link teardown is asynchronous and would race
      # the gateway restart and the other test's supervisor start.
      :ok = Supervisor.stop(pid)
    end

    test "starts empty supervisor when HOLOGRAM_START is not set" do
      System.delete_env("HOLOGRAM_START")

      assert {:ok, pid} = start(:my_app, :temporary)
      assert is_pid(pid)

      children = Supervisor.which_children(pid)
      assert children == []

      # Stop the app tree deterministically - link teardown is asynchronous and would race
      # the other test's supervisor start.
      :ok = Supervisor.stop(pid)
    end
  end
end
