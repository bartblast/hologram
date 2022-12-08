defmodule Hologram.Compiler.RelaxedBooleanOrOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.RelaxedBooleanOrOperator

  def transform({:||, _, [left, right]}, %Context{} = context) do
    %RelaxedBooleanOrOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
