defmodule Hologram.Compiler.UnaryPositiveOperatorTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.UnaryPositiveOperator
  alias Hologram.Compiler.Transformer

  def transform({:+, _, [value]}, %Context{} = context) do
    %UnaryPositiveOperator{
      value: Transformer.transform(value, context)
    }
  end
end
