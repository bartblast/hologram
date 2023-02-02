defmodule Hologram.Compiler.RelaxedBooleanOrOperatorTransformer do
  alias Hologram.Compiler.IR.RelaxedBooleanOrOperator
  alias Hologram.Compiler.Transformer

  def transform({:||, _, [left, right]}) do
    %RelaxedBooleanOrOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
