# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Stubs do
  import Hologram.Test.Helpers, only: [random_atom: 0, random_module: 0, random_string: 0]

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.Reflection
  alias Hologram.Router.PageModuleResolver

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
            random_string()
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
            "#{random_string()}.plt"
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
