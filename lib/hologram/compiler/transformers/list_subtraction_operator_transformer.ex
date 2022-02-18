defmodule Hologram.Compiler.ListSubtractionOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.ListSubtractionOperator

  def transform({:--, _, [left, right]}, %Context{} = context) do
    %ListSubtractionOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
