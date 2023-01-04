defmodule Hologram.Compiler.CallTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [module, function]}, _, args}, %Context{} = context) do
    build_call(module, function, args, context)
  end

  def transform({function, _, args}, %Context{} = context) do
    build_call(nil, function, args, context)
  end

  defp build_args(args, context) do
    args = if is_list(args), do: args, else: []
    Enum.map(args, &Transformer.transform(&1, context))
  end

  defp build_call(module, function, args, %Context{} = context) do
    module =
      if module do
        Transformer.transform(module, context)
      else
        nil
      end

    args = build_args(args, context)

    %Call{
      module: module,
      function: function,
      args: args
    }
  end
end
