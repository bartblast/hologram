defmodule Hologram.Compiler.IfExpressionTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.IfExpression

  def transform({:if, _, [condition, [do: do_block, else: else_block]]} = full_ast, %Context{} = context) do
    %IfExpression{
      condition: Transformer.transform(condition, context),
      do: Transformer.transform(do_block, context),
      else: Transformer.transform(else_block, context),
      ast: full_ast
    }
  end
end
