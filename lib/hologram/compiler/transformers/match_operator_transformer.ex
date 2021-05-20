defmodule Hologram.Compiler.MatchOperatorTransformer do
  alias Hologram.Compiler.IR.MatchOperator
  alias Hologram.Compiler.Binder
  alias Hologram.Compiler.Transformer

  def transform(left, right, context) do
    left = Transformer.transform(left, context)

    %MatchOperator{
      bindings: Binder.bind(left),
      left: left,
      right: Transformer.transform(right, context)
    }
  end
end
