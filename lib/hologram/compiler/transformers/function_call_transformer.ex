defmodule Hologram.Compiler.FunctionCallTransformer do
  alias Hologram.Compiler.{Context, Helpers, Resolver, Transformer}
  alias Hologram.Compiler.IR.{FunctionCall, ListType, NotSupportedExpression}

  def transform(
        {{:., _, [{:__aliases__, _, module_segs}, function]}, _, args},
        %Context{} = context
      ) do
    build_function_call(module_segs, function, args, context)
  end

  def transform({{:., _, [Kernel, :to_string]}, _, args}, %Context{} = context) do
    build_function_call([:Kernel], :to_string, args, context)
  end

  def transform({{:., _, [{:__MODULE__, _, _}, function]}, _, args}, %Context{} = context) do
    Helpers.module_name_segments(context.module)
    |> build_function_call(function, args, context)
  end

  def transform({{:., _, [erlang_module, _]}, _, _} = ast, _) when is_atom(erlang_module) do
    %NotSupportedExpression{ast: ast, type: :erlang_function_call}
  end

  def transform({{:., _, [module_expr, function]}, _, args}, %Context{} = context) do
    %FunctionCall{
      module: Kernel,
      function: :apply,
      args: [
        Transformer.transform(module_expr, context),
        Transformer.transform(function, context),
        %ListType{data: build_args(args, context)}
      ]
    }
  end

  def transform({function, _, args}, %Context{} = context) do
    build_function_call([], function, args, context)
  end

  defp build_function_call(module_segs, function, args, %Context{} = context) do
    args = build_args(args, context)
    arity = Enum.count(args)

    module =
      Resolver.resolve(
        module_segs,
        function,
        arity,
        context
      )

    %FunctionCall{module: module, function: function, args: args}
  end

  defp build_args(args, context) do
    args = if is_list(args), do: args, else: []
    Enum.map(args, &Transformer.transform(&1, context))
  end
end
