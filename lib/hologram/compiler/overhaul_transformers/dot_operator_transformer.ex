defmodule Hologram.Compiler.DotOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.DotOperator

  def transform({{:., _, [left, right]}, _, []}, %Context{} = context) do
    %DotOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end
end
