defmodule Hologram.Compiler.UnquoteTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.Unquote

  def transform({:unquote, _, [expr]}, %Context{} = context) do
    expr = Transformer.transform(expr, context)
    %Unquote{expression: expr}
  end
end
