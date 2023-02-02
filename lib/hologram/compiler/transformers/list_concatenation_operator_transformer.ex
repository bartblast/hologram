defmodule Hologram.Compiler.ListConcatenationOperatorTransformer do
  alias Hologram.Compiler.IR.ListConcatenationOperator
  alias Hologram.Compiler.Transformer

  def transform({:++, _, [left, right]}) do
    %ListConcatenationOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
