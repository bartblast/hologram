# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Stubs do
  import Hologram.Test.Helpers, only: [random_atom: 0, random_module: 0, random_string: 0]
  import Mox, only: [stub_with: 2]

  alias Hologram.Assets.ChunkRegistry
  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.ProcessUtils
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  # The name `mix phx.digest` gives a copy of an empty file, so that a fixture copy holds the content
  # of the empty file at its key, as a copy the asset path registry serves does.
  @empty_file_md5 "d41d8cd98f00b204e9800998ecf8427e"

  # The fixture pages the tests that start the page module resolver request.
  @page_module_resolver_pages [
    Hologram.Test.Fixtures.Router.Module1,
    Hologram.Test.Fixtures.Router.PageModuleResolver.Module1
  ]

  def setup_asset_manifest_cache(stub, start_link \\ true) do
    stub_with(AssetManifestCacheMock, stub)

    process_name = stub.process_name()

    if ProcessUtils.running?(process_name) do
      process_name
      |> Process.whereis()
      |> Process.exit(:kill)
    end

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

    mapping = setup_asset_fixtures(stub.static_dir(), stub.bundles_dir())

    if start_link do
      AssetPathRegistry.start_link([])
    end

    mapping
  end

  def setup_chunk_registry(stub, start_link \\ true) do
    stub_with(ChunkRegistryMock, stub)

    setup_chunk_registry_dump(stub)

    ets_table_name = stub.ets_table_name()

    if ETS.table_exists?(ets_table_name) do
      ETS.delete(ets_table_name)
    end

    if start_link do
      ChunkRegistry.start_link([])
    end

    :ok
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

    setup_page_module_resolver_dump(stub)

    :persistent_term.erase(stub.persistent_term_key())

    if start_link do
      PageModuleResolver.start_link([])
    end

    :ok
  end

  def setup_server(stub) do
    stub_with(ServerMock, stub)
    :ok
  end

  defmacro use_module_stub(:asset_manifest_cache) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).AssetManifestCacheStub) do
        @behaviour AssetManifestCache

        def persistent_term_key, do: unquote(random_atom())

        def process_name, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).AssetManifestCacheStub)
    end
  end

  defmacro use_module_stub(:asset_path_registry) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).AssetPathRegistryStub) do
        @behaviour AssetPathRegistry

        def bundles_dir do
          Path.join([
            Reflection.tmp_dir(),
            "tests",
            "stubs",
            "asset_path_registry",
            "bundles_dir_0",
            unquote(random_string())
          ])
        end

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

  defmacro use_module_stub(:chunk_registry) do
    random_module = random_module()

    quote do
      defmodule alias!(unquote(random_module).ChunkRegistryStub) do
        @behaviour ChunkRegistry

        def dump_path do
          Path.join([
            Reflection.tmp_dir(),
            "tests",
            "stubs",
            "chunk_registry",
            "dump_path_0",
            "#{unquote(random_string())}.plt"
          ])
        end

        def ets_table_name, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).ChunkRegistryStub)
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

        def dump_path do
          Path.join([
            Reflection.tmp_dir(),
            "tests",
            "stubs",
            "page_module_resolver",
            "dump_path_0",
            "#{unquote(random_string())}.plt"
          ])
        end

        def persistent_term_key, do: unquote(random_atom())
      end

      alias alias!(unquote(random_module).PageModuleResolverStub)
    end
  end

  defp setup_asset_fixtures(static_dir, bundles_dir) do
    FileUtils.recreate_dir(static_dir)
    FileUtils.recreate_dir(bundles_dir)

    dir_2 = static_dir <> "/test_dir_1/test_dir_2"
    file_2a_path = dir_2 <> "/test_file_1-#{@empty_file_md5}.css"
    file_2b_path = dir_2 <> "/test_file_2-#{@empty_file_md5}.css"
    file_2c_path = dir_2 <> "/page-#{@empty_file_md5}.js"
    file_2d_path = dir_2 <> "/page-#{@empty_file_md5}.js.map"
    file_2e_path = dir_2 <> "/test_file_1.css"
    file_2f_path = dir_2 <> "/test_file_2.css"
    file_2g_path = dir_2 <> "/page.js"

    dir_3 = static_dir <> "/test_dir_3"
    file_3a_path = dir_3 <> "/test_file_5.css"
    file_3b_path = dir_3 <> "/test_file_4-#{@empty_file_md5}.css"
    file_3c_path = dir_3 <> "/test_file_5-#{@empty_file_md5}.css"
    file_3d_path = dir_3 <> "/page-#{@empty_file_md5}.js"
    file_3e_path = dir_3 <> "/page-#{@empty_file_md5}.js.map"
    file_3f_path = dir_3 <> "/test_file_10.css"
    file_3g_path = dir_3 <> "/test_file_11-DOWNLOAD.css"
    file_3h_path = dir_3 <> "/test_file_4.css"
    file_3i_path = dir_3 <> "/page.js"

    file_4a_path = bundles_dir <> "/page-Elixir.MyPage1-BBBBBBBB.js"
    file_4b_path = bundles_dir <> "/page-Elixir.MyPage1-BBBBBBBB.js.map"
    file_4c_path = bundles_dir <> "/page-Elixir.MyPage2-CCCCCCCC.js"
    file_4d_path = bundles_dir <> "/page-Elixir.MyPage2-CCCCCCCC.js.map"
    file_4e_path = bundles_dir <> "/runtime-AAAAAAAA.js"
    file_4g_path = bundles_dir <> "/chunk-DDDDDDDD.js"
    file_4h_path = bundles_dir <> "/chunk-DDDDDDDD.js.map"

    File.mkdir_p!(dir_2)
    File.mkdir_p!(dir_3)

    file_paths = [
      file_2a_path,
      file_2b_path,
      file_2c_path,
      file_2d_path,
      file_2e_path,
      file_2f_path,
      file_2g_path,
      file_3a_path,
      file_3b_path,
      file_3c_path,
      file_3d_path,
      file_3e_path,
      file_3f_path,
      file_3g_path,
      file_3h_path,
      file_3i_path,
      file_4a_path,
      file_4b_path,
      file_4c_path,
      file_4d_path,
      file_4e_path,
      file_4g_path,
      file_4h_path
    ]

    Enum.each(file_paths, &File.write!(&1, ""))

    [
      mapping: %{
        "test_dir_1/test_dir_2/test_file_1.css" =>
          "/test_dir_1/test_dir_2/test_file_1-#{@empty_file_md5}.css",
        "test_dir_1/test_dir_2/test_file_2.css" =>
          "/test_dir_1/test_dir_2/test_file_2-#{@empty_file_md5}.css",
        "test_dir_1/test_dir_2/page.js" => "/test_dir_1/test_dir_2/page-#{@empty_file_md5}.js",
        "test_dir_3/test_file_4.css" => "/test_dir_3/test_file_4-#{@empty_file_md5}.css",
        "test_dir_3/test_file_5.css" => "/test_dir_3/test_file_5-#{@empty_file_md5}.css",
        "test_dir_3/test_file_10.css" => "/test_dir_3/test_file_10.css",
        "test_dir_3/test_file_11-DOWNLOAD.css" => "/test_dir_3/test_file_11-DOWNLOAD.css",
        "test_dir_3/page.js" => "/test_dir_3/page-#{@empty_file_md5}.js",
        "hologram/runtime.js" => "/hologram/runtime-AAAAAAAA.js"
      }
    ]
  end

  # Two pages, the second preloading no chunk, and two struct types that share a chunk.
  defp setup_chunk_registry_dump(stub) do
    dump_path = stub.dump_path()

    File.rm(dump_path)

    PLT.start()
    |> PLT.put({:page, :module_a}, ["AAAAAAAA", "CCCCCCCC"])
    |> PLT.put({:page, :module_b}, [])
    |> PLT.put({:type, Date}, ["BBBBBBBB", "CCCCCCCC"])
    |> PLT.put({:type, Time}, ["AAAAAAAA", "CCCCCCCC"])
    |> PLT.dump(dump_path)

    :ok
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

  # The module info PLT entries the resolver reads: the fixture pages with their routes.
  defp setup_page_module_resolver_dump(stub) do
    dump_path = stub.dump_path()

    File.rm(dump_path)

    items =
      Enum.map(@page_module_resolver_pages, fn page_module ->
        {page_module, %{page?: true, route: page_module.__route__()}}
      end)

    plt = PLT.start(items: items)
    PLT.dump(plt, dump_path)
    PLT.stop(plt)

    :ok
  end
end
