defmodule Hologram.Compiler.FunctionCallTransformer do
  alias Hologram.Compiler.IR.FunctionCall
  alias Hologram.Compiler.{Context, Resolver, Transformer}

  def transform(called_module, function, params, %Context{} = context) do
    params = transform_call_params(params, context)
    arity = Enum.count(params)

    resolved_module =
      Resolver.resolve(
        called_module,
        function,
        arity,
        context.imports,
        context.aliases,
        context.module
      )

    %FunctionCall{module: resolved_module, function: function, params: params}
  end

  defp transform_call_params(params, context) do
    Enum.map(params, &Transformer.transform(&1, context))
  end
end
