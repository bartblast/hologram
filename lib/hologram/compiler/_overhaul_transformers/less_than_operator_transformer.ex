defmodule Hologram.Compiler.LessThanOperatorTransformer do
  alias Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR.LessThanOperator

  def transform({:<, _, [left, right]}) do
    %LessThanOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
