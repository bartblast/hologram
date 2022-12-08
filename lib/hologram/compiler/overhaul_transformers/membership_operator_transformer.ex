defmodule Hologram.Compiler.MembershipOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.MembershipOperator

  def transform({:in, _, [left, right]}, %Context{} = context) do
    left = Transformer.transform(left, context)
    right = Transformer.transform(right, context)

    %MembershipOperator{left: left, right: right}
  end
end
