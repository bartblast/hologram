defmodule Hologram.Compiler.SubtractionOperatorTransformer do
  alias Hologram.Compiler.IR.SubtractionOperator
  alias Hologram.Compiler.Transformer

  def transform({:-, _, [left, right]}) do
    %SubtractionOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
