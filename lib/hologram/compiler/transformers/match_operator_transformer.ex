defmodule Hologram.Compiler.MatchOperatorTransformer do
  alias Hologram.Compiler.{Binder, Context, Transformer}
  alias Hologram.Compiler.IR.MatchOperator

  def transform({:=, _, [left, right]}, %Context{} = context) do
    left = Transformer.transform(left, context)

    %MatchOperator{
      bindings: Binder.bind(left),
      left: left,
      right: Transformer.transform(right, context)
    }
  end
end
