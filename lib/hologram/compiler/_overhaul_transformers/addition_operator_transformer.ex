defmodule Hologram.Compiler.AdditionOperatorTransformer do
  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.Transformer

  def transform({:+, _, [left, right]}) do
    %AdditionOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
