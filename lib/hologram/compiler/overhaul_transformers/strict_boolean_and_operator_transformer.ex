defmodule Hologram.Compiler.StrictBooleanAndOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.StrictBooleanAndOperator

  def transform({:and, _, [left, right]}, %Context{} = context) do
    %StrictBooleanAndOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
