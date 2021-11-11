defmodule Hologram.Compiler.MatchOperatorTransformer do
  alias Hologram.Compiler.{Binder, Context, Transformer}
  alias Hologram.Compiler.IR.MatchOperator

  def transform({:=, _, [left, right]}, %Context{} = context) do
    left = Transformer.transform(left, context)

    bindings =
      Binder.bind(left)
      |> Enum.map(fn path ->
        [head | tail] = Enum.reverse(path)
        {head.name, Enum.reverse(tail)}
      end)

    %MatchOperator{
      bindings: bindings,
      left: left,
      right: Transformer.transform(right, context)
    }
  end
end
