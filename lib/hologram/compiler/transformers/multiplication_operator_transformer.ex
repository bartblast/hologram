defmodule Hologram.Compiler.MultiplicationOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.MultiplicationOperator

  def transform({:*, _, [left, right]}, %Context{} = context) do
    %MultiplicationOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
