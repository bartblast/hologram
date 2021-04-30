defmodule Hologram.Transpiler.DotOperatorTransformer do
  alias Hologram.Transpiler.AST.DotOperator
  alias Hologram.Transpiler.Transformer

  def transform(left, right, context) do
    %DotOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
