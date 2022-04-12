defmodule Hologram.Compiler.ConsOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.ConsOperator

  def transform([{:|, _, [head, tail]}], %Context{} = context) do
    %ConsOperator{
      head: Transformer.transform(head, context),
      tail: Transformer.transform(tail, context)
    }
  end
end
