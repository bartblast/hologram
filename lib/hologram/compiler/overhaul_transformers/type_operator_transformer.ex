defmodule Hologram.Compiler.TypeOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.TypeOperator

  def transform({:"::", _, [left, {right, _, _}]}, %Context{} = context) do
    left = Transformer.transform(left, context)
    %TypeOperator{left: left, right: right}
  end
end
