defmodule Hologram.Compiler.MultiplicationOperatorTransformer do
  alias Hologram.Compiler.IR.MultiplicationOperator
  alias Hologram.Compiler.Transformer

  def transform({:*, _, [left, right]}) do
    %MultiplicationOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end
end
