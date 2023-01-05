defmodule Hologram.Compiler.DivisionOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.DivisionOperator

  def transform({:/, _, [left, right]}, %Context{} = context) do
    %DivisionOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
