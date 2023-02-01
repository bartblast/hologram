defmodule Hologram.Compiler.CallTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [module, function]}, _, args}, %Context{} = context) do
    build_call(module, function, args, context)
  end

  def transform({function, [context: _, imports: [{_arity, module}]], args}, %Context{} = context) do
    segments = Helpers.alias_segments(module)
    module_ir = %IR.ModuleType{module: module, segments: segments}
    build_call(module_ir, function, args, context)
  end

  def transform({function, _, args}, %Context{} = context) do
    build_call(nil, function, args, context)
  end

  defp build_call(module, function, args, %Context{} = context) do
    args = if is_list(args), do: args, else: []

    %IR.Call{
      module: build_module(module, context),
      function: function,
      args: transform_args(args, context),
      args_ast: args
    }
  end

  defp build_module(module, context) do
    case module do
      nil ->
        nil

      %IR.ModuleType{} ->
        module

      module ->
        Transformer.transform(module, context)
    end
  end

  defp transform_args(args, context) do
    Enum.map(args, &Transformer.transform(&1, context))
  end
end
