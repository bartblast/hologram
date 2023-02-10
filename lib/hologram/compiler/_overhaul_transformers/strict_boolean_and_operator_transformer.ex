defmodule Hologram.Compiler.StrictBooleanAndOperatorTransformer do
  alias Hologram.Compiler.IR.StrictBooleanAndOperator
  alias Hologram.Compiler.Transformer

  def transform({:and, _, [left, right]}) do
    %StrictBooleanAndOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
