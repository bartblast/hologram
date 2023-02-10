defmodule Hologram.Compiler.EqualToOperatorTransformer do
  alias Hologram.Compiler.IR.EqualToOperator
  alias Hologram.Compiler.Transformer

  def transform({:==, _, [left, right]}) do
    %EqualToOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
