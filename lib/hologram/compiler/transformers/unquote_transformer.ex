defmodule Hologram.Compiler.UnquoteTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.Unquote
  alias Hologram.Compiler.Transformer

  def transform({:unquote, _, [expr]}, %Context{} = context) do
    expr = Transformer.transform(expr, context)
    %Unquote{expression: expr}
  end
end
