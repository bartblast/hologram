defmodule Hologram.Compiler.ListTypeTransformer do
  alias Hologram.Compiler.AST.ListType
  alias Hologram.Compiler.Transformer

  def transform(list, context) do
    data = Enum.map(list, &Transformer.transform(&1, context))
    %ListType{data: data}
  end
end
