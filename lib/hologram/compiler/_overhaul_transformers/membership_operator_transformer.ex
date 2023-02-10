defmodule Hologram.Compiler.MembershipOperatorTransformer do
  alias Hologram.Compiler.IR.MembershipOperator
  alias Hologram.Compiler.Transformer

  def transform({:in, _, [left, right]}) do
    left = Transformer.transform(left)
    right = Transformer.transform(right)

    %MembershipOperator{left: left, right: right}
  end
end
