defmodule Hologram.Compiler.DotOperatorTransformer do
  alias Hologram.Compiler.AST.DotOperator
  alias Hologram.Compiler.Transformer

  def transform(left, right, context) do
    %DotOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
