defmodule Hologram.Compiler.Context do
  defstruct module: nil,
            uses: [],
            imports: [],
            requires: [],
            aliases: %{},
            attributes: [],
            block_bindings: [],
            functions: %{},
            macros: %{},
            module_attributes: %{},
            variables: MapSet.new()

  def put_functions(%{functions: defined_functions} = context, module, functions) do
    added_functions = aggregate_merged_exports(module, functions)
    %{context | functions: DeepMerge.deep_merge(defined_functions, added_functions)}
  end

  def put_macros(%{macros: defined_macros} = context, module, macros) do
    added_macros = aggregate_merged_exports(module, macros)
    %{context | macros: DeepMerge.deep_merge(defined_macros, added_macros)}
  end

  def put_module_attribute(
        %{module_attributes: module_attributes} = context,
        name,
        value
      ) do
    %{context | module_attributes: Map.put(module_attributes, name, value)}
  end

  defp aggregate_merged_exports(module, exports) do
    Enum.reduce(exports, %{}, fn {name, arity}, acc ->
      export = %{name => %{arity => module}}
      DeepMerge.deep_merge(acc, export)
    end)
  end
end
