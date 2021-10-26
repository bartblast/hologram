defmodule Hologram.Compiler.FunctionCallTransformer do
  alias Hologram.Compiler.{Context, Helpers, Resolver, Transformer}
  alias Hologram.Compiler.IR.{FunctionCall, NotSupportedExpression}

  def transform(
        {{:., _, [{:__aliases__, _, module_segs}, function]}, _, params},
        %Context{} = context
      ) do
    build_function_call(module_segs, function, params, context)
  end

  def transform({{:., _, [Kernel, :to_string]}, _, params}, %Context{} = context) do
    build_function_call([:Kernel], :to_string, params, context)
  end

  def transform({{:., _, [{:__MODULE__, _, _}, function]}, _, params}, %Context{} = context) do
    Helpers.module_segments(context.module)
    |> build_function_call(function, params, context)
  end

  def transform({{:., _, [erlang_module, _]}, _, _} = ast, _) when is_atom(erlang_module) do
    %NotSupportedExpression{ast: ast, type: :erlang_function_call}
  end

  def transform({{:., _, [module_expr, function]}, _, params}, %Context{} = context) do
    %FunctionCall{
      module: Kernel,
      function: :apply,
      params: [
        Transformer.transform(module_expr, context),
        Transformer.transform(function, context),
        build_params(params, context)
      ]
    }
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
