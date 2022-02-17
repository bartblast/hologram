defmodule Hologram.Compiler.UnaryNegativeOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.UnaryNegativeOperator

  def transform({:-, _, [value]}, %Context{} = context) do
    %UnaryNegativeOperator{
      value: Transformer.transform(value, context)
    }
  end
end
