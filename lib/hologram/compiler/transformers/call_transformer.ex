defmodule Hologram.Compiler.CallTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [module, function]}, _, args}) do
    build_call(module, function, args)
  end

  def transform({symbol, [context: _, imports: _] = metadata, args})
      when not is_list(args) do
    transform({symbol, metadata, []})
  end

  def transform({function, [context: _, imports: [{_arity, module}]], args}) do
    segments = Helpers.alias_segments(module)
    module_ir = %IR.ModuleType{module: module, segments: segments}
    build_call(module_ir, function, args)
  end

  def transform({function, _, args}) do
    build_call(nil, function, args)
  end

  defp build_call(module, function, args) do
    args = if is_list(args), do: args, else: []

    %IR.Call{
      module: build_module(module),
      function: function,
      args: transform_args(args),
      args_ast: args
    }
  end

  defp build_module(module) do
    case module do
      nil ->
        nil

      %IR.ModuleType{} ->
        module

      module ->
        Transformer.transform(module)
    end
  end

  defp transform_args(args) do
    Enum.map(args, &Transformer.transform/1)
  end
end
