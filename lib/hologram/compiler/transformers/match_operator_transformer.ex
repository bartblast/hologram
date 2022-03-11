defmodule Hologram.Compiler.MatchOperatorTransformer do
  alias Hologram.Compiler.{Context, PatternBinder, Transformer}
  alias Hologram.Compiler.IR.{Binding, MatchOperator, VariableAccess}

  def transform({:=, _, [left, right]}, %Context{} = context) do
    left = Transformer.transform(left, context)

    bindings =
      PatternBinder.bind(left)
      |> Enum.map(fn path ->
        [head | tail] = Enum.reverse(path)
        access_path = [%VariableAccess{name: "window.$rightHandSide"} | Enum.reverse(tail)]
        %Binding{name: head.name, access_path: access_path}
      end)

    %MatchOperator{
      bindings: bindings,
      left: left,
      right: Transformer.transform(right, context)
    }
  end
end
