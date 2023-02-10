defmodule Hologram.Compiler.TypeOperatorTransformer do
  alias Hologram.Compiler.IR.TypeOperator
  alias Hologram.Compiler.Transformer

  def transform({:"::", _, [left, {right, _, _}]}) do
    left = Transformer.transform(left)
    %TypeOperator{left: left, right: right}
  end
end
