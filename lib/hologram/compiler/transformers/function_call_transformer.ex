defmodule Hologram.Compiler.FunctionCallTransformer do
  alias Hologram.Compiler.IR.FunctionCall
  alias Hologram.Compiler.{Context, Resolver, Transformer}

  def transform(module_segs, function, params, %Context{} = context) do
    params = transform_call_params(params, context)
    arity = Enum.count(params)

    module =
      Resolver.resolve(
        module_segs,
        function,
        arity,
        context.imports,
        context.aliases,
        context.module
      )

    %FunctionCall{module: module, function: function, params: params}
  end

  defp transform_call_params(params, context) do
    params = unless is_list(params), do: [], else: params
    Enum.map(params, &Transformer.transform(&1, context))
  end
end
