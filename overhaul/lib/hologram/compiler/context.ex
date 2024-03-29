defmodule Hologram.Compiler.Context do
  alias Hologram.Compiler.Reflection

  defstruct aliases: %{},
            block_bindings: [],
            functions: %{},
            macros: %{},
            module: nil,
            module_attributes: %{},
            variables: MapSet.new()

  # TODO: build env fields based on context data
  def build_env(_context) do
    %Macro.Env{}
  end

  def new do
    %__MODULE__{}
    |> put_functions(Kernel, Reflection.functions(Kernel))
    |> put_macros(Kernel, Reflection.macros(Kernel))
  end

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

  def resolve_function_module(context, name, arity) do
    context.functions[name][arity]
  end

  def resolve_macro_module(context, name, arity) do
    context.macros[name][arity]
  end

  defp aggregate_merged_exports(module, exports) do
    Enum.reduce(exports, %{}, fn {name, arity}, acc ->
      export = %{name => %{arity => module}}
      DeepMerge.deep_merge(acc, export)
    end)
  end
end
