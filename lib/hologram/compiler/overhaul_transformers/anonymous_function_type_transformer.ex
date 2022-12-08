defmodule Hologram.Compiler.AnonymousFunctionTypeTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.AnonymousFunctionType
  alias Hologram.Compiler.IR.NotSupportedExpression

  def transform({:fn, _, [{:->, _, [params, body]}]}, %Context{} = context) do
    params = Helpers.transform_params(params, context)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = Transformer.transform(body, context)

    %AnonymousFunctionType{arity: arity, params: params, bindings: bindings, body: body}
  end

  # TODO: implement anonymous functions with multiple clauses
  def transform(ast, _) do
    %NotSupportedExpression{
      ast: ast,
      type: :multi_clause_anonymous_function_type
    }
  end
end
