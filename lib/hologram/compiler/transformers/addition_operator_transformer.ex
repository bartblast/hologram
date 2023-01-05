defmodule Hologram.Compiler.AdditionOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.AdditionOperator

  def transform({:+, _, [left, right]}, %Context{} = context) do
    %AdditionOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
