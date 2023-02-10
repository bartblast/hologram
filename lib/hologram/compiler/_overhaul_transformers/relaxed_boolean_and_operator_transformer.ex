defmodule Hologram.Compiler.RelaxedBooleanAndOperatorTransformer do
  alias Hologram.Compiler.IR.RelaxedBooleanAndOperator
  alias Hologram.Compiler.Transformer

  def transform({:&&, _, [left, right]}) do
    %RelaxedBooleanAndOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
