defmodule Hologram.Compiler.LessThanOperatorTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR.LessThanOperator

  def transform({:<, _, [left, right]}, %Context{} = context) do
    %LessThanOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
