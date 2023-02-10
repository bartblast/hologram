defmodule Hologram.Compiler.ListSubtractionOperatorTransformer do
  alias Hologram.Compiler.IR.ListSubtractionOperator
  alias Hologram.Compiler.Transformer

  def transform({:--, _, [left, right]}) do
    %ListSubtractionOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
