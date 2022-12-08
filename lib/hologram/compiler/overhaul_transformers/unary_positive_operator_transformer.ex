defmodule Hologram.Compiler.UnaryPositiveOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.UnaryPositiveOperator

  def transform({:+, _, [value]}, %Context{} = context) do
    %UnaryPositiveOperator{
      value: Transformer.transform(value, context)
    }
  end
end
