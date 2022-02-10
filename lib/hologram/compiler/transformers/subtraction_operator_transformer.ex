defmodule Hologram.Compiler.SubtractionOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.SubtractionOperator

  def transform({:-, _, [left, right]}, %Context{} = context) do
    %SubtractionOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
