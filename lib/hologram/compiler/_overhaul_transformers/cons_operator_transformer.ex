defmodule Hologram.Compiler.ConsOperatorTransformer do
  alias Hologram.Compiler.IR.ConsOperator
  alias Hologram.Compiler.Transformer

  def transform([{:|, _, [head, tail]}]) do
    %ConsOperator{
      head: Transformer.transform(head),
      tail: Transformer.transform(tail)
    }
  end
end
