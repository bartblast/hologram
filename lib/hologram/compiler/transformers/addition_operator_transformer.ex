defmodule Hologram.Compiler.AdditionOperatorTransformer do
  alias Hologram.Compiler.AST.AdditionOperator
  alias Hologram.Compiler.Transformer

  def transform(left, right, context) do
    %AdditionOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
