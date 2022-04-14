defmodule Hologram.Compiler.NotEqualToOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.NotEqualToOperator

  def transform({:!=, _, [left, right]}, %Context{} = context) do
    %NotEqualToOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
