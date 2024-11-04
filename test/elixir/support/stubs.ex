# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Stubs do
  import Hologram.Test.Helpers, only: [random_atom: 0, random_module: 0, random_string: 0]

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.PLT
  alias Hologram.Reflection
  alias Hologram.Router.PageModuleResolver

  @doc """
  Sets up page digest registry process.
  """
  @spec setup_page_digest_registry(module) :: :ok
  def setup_page_digest_registry(stub) do
    setup_page_digest_registry_dump(stub)
    PageDigestRegistry.start_link([])

    :ok
  end

  @doc """
  Sets up page digest registry dump file.
  """
  @spec setup_page_digest_registry_dump(module) :: :ok
  def setup_page_digest_registry_dump(stub) do
    dump_path = stub.dump_path()

    File.rm(dump_path)

    PLT.start()
    |> PLT.put(:module_a, :module_a_digest)
    |> PLT.put(:module_b, :module_b_digest)
    |> PLT.put(:module_c, :module_c_digest)
    |> PLT.dump(dump_path)

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
end
