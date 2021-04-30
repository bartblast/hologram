defmodule Hologram.Transpiler.AdditionOperatorTransformer do
  alias Hologram.Transpiler.AST.AdditionOperator
  alias Hologram.Transpiler.Transformer

  def transform(left, right, context) do
    %AdditionOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
