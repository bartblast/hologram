# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Stubs do
  import Hologram.Test.Helpers, only: [random_atom: 0, random_module: 0, random_string: 0]
  import Mox, only: [stub_with: 2]

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.ProcessUtils
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  def setup_asset_manifest_cache(stub, start_link \\ true) do
    stub_with(AssetManifestCacheMock, stub)

    :persistent_term.erase(stub.persistent_term_key())

    if start_link do
      AssetManifestCache.start_link([])
    end

    :ok
  end

  def setup_asset_path_registry(stub, start_link \\ true) do
    stub_with(AssetPathRegistryMock, stub)

    process_name = stub.process_name()

    if ProcessUtils.running?(process_name) do
      process_name
      |> Process.whereis()
      |> Process.exit(:kill)
    end

    ets_table_name = stub.ets_table_name()

    if ETS.table_exists?(ets_table_name) do
      ETS.delete(ets_table_name)
    end

    mapping = setup_asset_fixtures(stub.static_dir())

    if start_link do
      AssetPathRegistry.start_link([])
    end

    mapping
  end

  def setup_page_digest_registry(stub, start_link \\ true) do
    stub_with(PageDigestRegistryMock, stub)

    setup_page_digest_registry_dump(stub)

    ets_table_name = stub.ets_table_name()

    if ETS.table_exists?(ets_table_name) do
      ETS.delete(ets_table_name)
    end

    if start_link do
      PageDigestRegistry.start_link([])
    end

    :ok
  end

  def setup_page_module_resolver(stub, start_link \\ true) do
    stub_with(PageModuleResolverMock, stub)

    :persistent_term.erase(stub.persistent_term_key())

    if start_link do
      PageModuleResolver.start_link([])
    end

    :ok
  end

  defmacro use_module_stub(:asset_manifest_cache) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).AssetManifestCacheStub) do
        @behaviour AssetManifestCache

        def persistent_term_key, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).AssetManifestCacheStub)
    end
  end

  defmacro use_module_stub(:asset_path_registry) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).AssetPathRegistryStub) do
        @behaviour AssetPathRegistry

        def static_dir do
          Path.join([
            Reflection.tmp_dir(),
            "tests",
            "stubs",
            "asset_path_registry",
            "static_dir_0",
            unquote(random_string())
          ])
        end

        def ets_table_name, do: unquote(random_atom())

        def process_name, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).AssetPathRegistryStub)
    end
  end

  defmacro use_module_stub(:page_digest_registry) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).PageDigestRegistryStub) do
        @behaviour PageDigestRegistry

        def dump_path do
          Path.join([
            Reflection.tmp_dir(),
            "tests",
            "stubs",
            "page_digest_registry",
            "dump_path_0",
            "#{unquote(random_string())}.plt"
          ])
        end

        def ets_table_name, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).PageDigestRegistryStub)
    end
  end

  defmacro use_module_stub(:page_module_resolver) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).PageModuleResolverStub) do
        @behaviour PageModuleResolver

        def persistent_term_key, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).PageModuleResolverStub)
    end
  end

  # credo:disable-for-lines:71 Credo.Check.Refactor.ABCSize
  defp setup_asset_fixtures(static_dir) do
    FileUtils.recreate_dir(static_dir)

    dir_2 = static_dir <> "/test_dir_1/test_dir_2"
    file_2a_path = dir_2 <> "/test_file_1-11111111111111111111111111111111.css"
    file_2b_path = dir_2 <> "/test_file_2-22222222222222222222222222222222.css"
    file_2c_path = dir_2 <> "/page-33333333333333333333333333333333.js"
    file_2d_path = dir_2 <> "/page-33333333333333333333333333333333.js.map"
    file_2e_path = dir_2 <> "/test_file_1.css"

    dir_3 = static_dir <> "/test_dir_3"
    file_3a_path = dir_3 <> "/test_file_5.css"
    file_3b_path = dir_3 <> "/test_file_4-44444444444444444444444444444444.css"
    file_3c_path = dir_3 <> "/test_file_5-55555555555555555555555555555555.css"
    file_3d_path = dir_3 <> "/page-66666666666666666666666666666666.js"
    file_3e_path = dir_3 <> "/page-66666666666666666666666666666666.js.map"
    file_3f_path = dir_3 <> "/test_file_10.css"

    dir_4 = static_dir <> "/hologram"
    file_4a_path = dir_4 <> "/page-77777777777777777777777777777777.js"
    file_4b_path = dir_4 <> "/page-77777777777777777777777777777777.js.map"
    file_4c_path = dir_4 <> "/page-88888888888888888888888888888888.js"
    file_4d_path = dir_4 <> "/page-88888888888888888888888888888888.js.map"
    file_4e_path = dir_4 <> "/runtime-00000000000000000000000000000000.js"
    file_4f_path = dir_4 <> "/test_file_9-99999999999999999999999999999999.css"

    File.mkdir_p!(dir_2)
    File.mkdir_p!(dir_3)
    File.mkdir_p!(dir_4)

    file_paths = [
      file_2a_path,
      file_2b_path,
      file_2c_path,
      file_2d_path,
      file_2e_path,
      file_3a_path,
      file_3b_path,
      file_3c_path,
      file_3d_path,
      file_3e_path,
      file_3f_path,
      file_4a_path,
      file_4b_path,
      file_4c_path,
      file_4d_path,
      file_4e_path,
      file_4f_path
    ]

    Enum.each(file_paths, &File.write!(&1, ""))

    [
      mapping: %{
        "test_dir_1/test_dir_2/test_file_1.css" =>
          "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
        "test_dir_1/test_dir_2/test_file_2.css" =>
          "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
        "test_dir_1/test_dir_2/page.js" =>
          "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
        "test_dir_3/test_file_4.css" =>
          "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
        "test_dir_3/test_file_5.css" =>
          "/test_dir_3/test_file_5-55555555555555555555555555555555.css",
        "test_dir_3/test_file_10.css" => "/test_dir_3/test_file_10.css",
        "test_dir_3/page.js" => "/test_dir_3/page-66666666666666666666666666666666.js",
        "hologram/runtime.js" => "/hologram/runtime-00000000000000000000000000000000.js",
        "hologram/test_file_9.css" => "/hologram/test_file_9-99999999999999999999999999999999.css"
      }
    ]
  end

  defp setup_page_digest_registry_dump(stub) do
    dump_path = stub.dump_path()

    File.rm(dump_path)

    PLT.start()
    |> PLT.put(:module_a, :module_a_digest)
    |> PLT.put(:module_b, :module_b_digest)
    |> PLT.put(:module_c, :module_c_digest)
    |> PLT.dump(dump_path)

    :ok
  end
end
