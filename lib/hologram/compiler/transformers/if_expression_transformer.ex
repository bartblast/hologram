defmodule Hologram.Compiler.IfExpressionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.IfExpression

  def transform({:if, _, [condition, [do: do_ast]]} = ast, %Context{} = context) do
    do_body = Helpers.fetch_block_body(do_ast)
    build_if_expression(condition, do_body, [nil], ast, context)
  end

  def transform({:if, _, [condition, [do: do_ast, else: else_ast]]} = ast, %Context{} = context) do
    do_body = Helpers.fetch_block_body(do_ast)
    else_body = Helpers.fetch_block_body(else_ast)
    build_if_expression(condition, do_body, else_body, ast, context)
  end

  defp build_if_expression(condition, do_body, else_body, ast, context) do
    condition = Transformer.transform(condition, context)
    do_body = Enum.map(do_body, &Transformer.transform(&1, context))
    else_body = Enum.map(else_body, &Transformer.transform(&1, context))

    %IfExpression{condition: condition, do: do_body, else: else_body, ast: ast}
  end
end
