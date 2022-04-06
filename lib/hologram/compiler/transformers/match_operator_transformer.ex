defmodule Hologram.Compiler.MatchOperatorTransformer do
  alias Hologram.Compiler.{Bindings, Context, Transformer}
  alias Hologram.Compiler.IR.{Binding, MatchAccess, MatchOperator}

  def transform({:=, _, [left, right]}, %Context{} = context) do
    left = Transformer.transform(left, context)

    bindings =
      Bindings.find(left)
      |> Enum.map(fn path ->
        [head | tail] = Enum.reverse(path)
        access_path = [%MatchAccess{} | Enum.reverse(tail)]
        %Binding{name: head.name, access_path: access_path}
      end)

    %MatchOperator{
      bindings: bindings,
      left: left,
      right: Transformer.transform(right, context)
    }
  end
end
