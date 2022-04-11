defmodule Hologram.Compiler.ListTypeTransformer do
  alias Hologram.Compiler.{ConsOperatorTransformer, Context, Transformer}
  alias Hologram.Compiler.IR.ListType

  def transform([{:|, _, _} = ast], %Context{} = context) do
    data = ConsOperatorTransformer.transform(ast, context)
    %ListType{data: data}
  end

  def transform(ast, %Context{} = context) do
    data = Enum.map(ast, &Transformer.transform(&1, context))
    %ListType{data: data}
  end
end
