defmodule Hologram.Compiler.EqualToOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.EqualToOperator

  def transform({:==, _, [left, right]}, %Context{} = context) do
    %EqualToOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
