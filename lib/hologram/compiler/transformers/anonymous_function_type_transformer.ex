defmodule Hologram.Compiler.AnonymousFunctionTypeTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.{AnonymousFunctionType, NotSupportedExpression}

  def transform({:fn, _, [{:->, _, [params, ast]}]}, %Context{} = context) do
    params = Helpers.transform_params(params, context)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)

    body =
      Helpers.fetch_block_body(ast)
      |> Enum.map(&Transformer.transform(&1, context))

    %AnonymousFunctionType{arity: arity, params: params, bindings: bindings, body: body}
  end

  # DEFER: implement
  def transform(ast, %Context{}) do
    %NotSupportedExpression{ast: ast, type: :anonymous_function_type}
  end
end
