defmodule Hologram.Compiler.RelaxedBooleanAndOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.RelaxedBooleanAndOperator

  def transform({:&&, _, [left, right]}, %Context{} = context) do
    %RelaxedBooleanAndOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
