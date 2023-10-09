defmodule Hologram.Test.Stubs do
  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.AssetPathRegistry

  defmacro use_module_stub(:asset_path_registry) do
    caller_module = __CALLER__.module

    quote do
      defmodule alias!(unquote(caller_module).AssetPathRegistryStub) do
        @behaviour AssetPathRegistry

        def static_dir_path, do: "#{Reflection.tmp_path()}/#{unquote(caller_module)}"

        def ets_table_name, do: unquote(caller_module)

        def process_name, do: unquote(caller_module)
      end

      alias alias!(unquote(caller_module).AssetPathRegistryStub)
    end
  end
end
