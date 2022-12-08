defmodule Hologram.Compiler.ListConcatenationOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.ListConcatenationOperator

  def transform({:++, _, [left, right]}, %Context{} = context) do
    %ListConcatenationOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
