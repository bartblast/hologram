defmodule Hologram.Compiler.IfExpressionTransformer do
  alias Hologram.Compiler.IR.IfExpression
  alias Hologram.Compiler.Transformer

  def transform({:if, _, [condition, [do: do_block, else: else_block]]} = ast) do
    %IfExpression{
      condition: Transformer.transform(condition),
      do: Transformer.transform(do_block),
      else: Transformer.transform(else_block),
      ast: ast
    }
  end
end
