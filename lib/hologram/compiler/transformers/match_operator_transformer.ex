defmodule Hologram.Compiler.MatchOperatorTransformer do
  alias Hologram.Compiler.{Context, PatternBinder, Transformer}
  alias Hologram.Compiler.IR.MatchOperator

  def transform({:=, _, [left, right]}, %Context{} = context) do
    left = Transformer.transform(left, context)

    bindings =
      PatternBinder.bind(left)
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
