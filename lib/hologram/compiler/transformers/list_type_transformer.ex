defmodule Hologram.Compiler.ListTypeTransformer do
  alias Hologram.Compiler.IR.ListType
  alias Hologram.Compiler.Transformer

  def transform(ast, context) do
    data = Enum.map(ast, &Transformer.transform(&1, context))
    %ListType{data: data}
  end
end
