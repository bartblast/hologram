defmodule Hologram.Compiler.BooleanAndOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.BooleanAndOperator

  def transform({:&&, _, [left, right]}, %Context{} = context) do
    %BooleanAndOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
