defmodule Hologram.Compiler.UnaryNegativeOperatorTransformer do
  alias Hologram.Compiler.IR.UnaryNegativeOperator
  alias Hologram.Compiler.Transformer

  def transform({:-, _, [value]}) do
    %UnaryNegativeOperator{
      value: Transformer.transform(value)
    }
  end
end
