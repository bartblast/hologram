defmodule Hologram.Compiler.FunctionCallTransformer do
  alias Hologram.Compiler.IR.{FunctionCall, NotSupportedExpression}
  alias Hologram.Compiler.{Context, Helpers, Resolver, Transformer}

  def transform({{:., _, [{:__aliases__, _, module_segs}, function]}, _, params}, %Context{} = context) do
    build_function_call(module_segs, function, params, context)
  end

  def transform({{:., _, [Kernel, :to_string]}, _, params}, %Context{} = context) do
    build_function_call([:Kernel], :to_string, params, context)
  end

  def transform({{:., _, [{:__MODULE__, _, _}, function]}, _, params}, %Context{} = context) do
    Helpers.module_segments(context.module)
    |> build_function_call(function, params, context)
  end

  def transform({{:., _, [_, _]}, _, _} = ast, _) do
    %NotSupportedExpression{ast: ast, type: :erlang_function_call}
  end

  def transform({function, _, params}, %Context{} = context) do
    build_function_call([], function, params, context)
  end

  defp build_function_call(module_segs, function, params, %Context{} = context) do
    params = build_params(params, context)
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

  defp build_params(params, context) do
    params = unless is_list(params), do: [], else: params
    Enum.map(params, &Transformer.transform(&1, context))
  end
end
