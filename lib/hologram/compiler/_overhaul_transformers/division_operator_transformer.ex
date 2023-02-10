defmodule Hologram.Compiler.DivisionOperatorTransformer do
  alias Hologram.Compiler.IR.DivisionOperator
  alias Hologram.Compiler.Transformer

  def transform({:/, _, [left, right]}) do
    %DivisionOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
