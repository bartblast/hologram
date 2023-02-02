defmodule Hologram.Compiler.NotEqualToOperatorTransformer do
  alias Hologram.Compiler.IR.NotEqualToOperator
  alias Hologram.Compiler.Transformer

  def transform({:!=, _, [left, right]}) do
    %NotEqualToOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
