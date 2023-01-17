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
            variables: MapSet.new()

  def put_functions(%__MODULE__{functions: defined_functions} = context, module, functions) do
    added_functions =
      Enum.reduce(functions, %{}, fn {name, arity}, acc ->
        function = %{name => %{arity => module}}
        DeepMerge.deep_merge(acc, function)
      end)

    %{context | functions: DeepMerge.deep_merge(defined_functions, added_functions)}
  end
end
