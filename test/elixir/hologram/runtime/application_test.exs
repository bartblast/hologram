defmodule Hologram.Runtime.ApplicationTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.Application
  import Mox

  alias Hologram.Commons.Reflection
  alias Hologram.Router.PageModuleResover
  alias Hologram.Runtime.AssetManifestCache
  alias Hologram.Runtime.AssetPathRegistry
  alias Hologram.Runtime.PageDigestRegistry

  defmodule PageModuleResoverStub do
    @behaviour PageModuleResover

    def persistent_term_key, do: __MODULE__
  end

  defmodule AssetManifestCacheStub do
    @behaviour AssetManifestCache

    def persistent_term_key, do: __MODULE__
  end

  defmodule PageDigestRegistryStub do
    @behaviour PageDigestRegistry

    def dump_path, do: "#{Reflection.tmp_path()}/#{__MODULE__}.plt"

    def ets_table_name, do: __MODULE__
  end

  use_module_stub AssetPathRegistryStub

  setup :set_mox_global

  setup do
    stub_with(PageModuleResover.Mock, PageModuleResoverStub)
    stub_with(AssetManifestCache.Mock, AssetManifestCacheStub)
    stub_with(AssetPathRegistry.Mock, AssetPathRegistryStub)
    stub_with(PageDigestRegistry.Mock, PageDigestRegistryStub)

    clean_dir(AssetPathRegistryStub.static_dir_path())
    setup_asset_fixtures(AssetPathRegistryStub.static_dir_path())

    setup_page_digest_registry_dump(PageDigestRegistryStub)

    :ok
  end

  test "start/2" do
    assert {:ok, pid} = start(:my_app, :temporary)
    assert is_pid(pid)
  end
end
