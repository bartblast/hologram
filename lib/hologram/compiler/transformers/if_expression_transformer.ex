defmodule Hologram.Compiler.IfExpressionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.{Block, IfExpression}

  def transform({:if, _, [condition, [do: do_ast]]} = ast, %Context{} = context) do
    do_exprs = Helpers.get_block_expressions(do_ast)
    build_if_exprs(condition, do_exprs, [nil], ast, context)
  end

  def transform({:if, _, [condition, [do: do_ast, else: else_ast]]} = full_ast, %Context{} = context) do
    do_exprs = Helpers.get_block_expressions(do_ast)
    else_exprs = Helpers.get_block_expressions(else_ast)
    build_if_exprs(condition, do_exprs, else_exprs, full_ast, context)
  end

  defp build_if_exprs(condition, do_exprs, else_exprs, full_ast, context) do
    condition = Transformer.transform(condition, context)

    do_exprs = Enum.map(do_exprs, &Transformer.transform(&1, context))
    do_block = %Block{expressions: do_exprs}

    else_exprs = Enum.map(else_exprs, &Transformer.transform(&1, context))
    else_block = %Block{expressions: else_exprs}

    %IfExpression{condition: condition, do: do_block, else: else_block, ast: full_ast}
  end
end
