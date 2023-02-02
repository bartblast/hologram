defmodule Hologram.Compiler.UnaryPositiveOperatorTransformer do
  alias Hologram.Compiler.IR.UnaryPositiveOperator
  alias Hologram.Compiler.Transformer

  def transform({:+, _, [value]}) do
    %UnaryPositiveOperator{
      value: Transformer.transform(value)
    }
  end
end
