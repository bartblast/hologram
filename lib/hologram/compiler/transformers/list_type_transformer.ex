defmodule Hologram.Compiler.ListTypeTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.ListType

  def transform(ast, %Context{} = context) do
    data = Enum.map(ast, &Transformer.transform(&1, context))
    %ListType{data: data}
  end
end
