defmodule Hologram.Compiler.UnquoteTransformer do
  alias Hologram.Compiler.IR.Unquote
  alias Hologram.Compiler.Transformer

  def transform({:unquote, _, [expr]}) do
    expr = Transformer.transform(expr)
    %Unquote{expression: expr}
  end
end
