defmodule Hologram.Test.Stubs do
  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.AssetPathRegistry

  defmacro use_module_stub({:__aliases__, _meta, [:AssetPathRegistryStub]}) do
    caller_module = __CALLER__.module

    quote do
      defmodule alias!(AssetPathRegistryStub) do
        @behaviour AssetPathRegistry

        def static_dir_path, do: "#{Reflection.tmp_path()}/#{unquote(caller_module)}"

        def ets_table_name, do: unquote(caller_module)

        def process_name, do: unquote(caller_module)
      end
    end
  end
end
