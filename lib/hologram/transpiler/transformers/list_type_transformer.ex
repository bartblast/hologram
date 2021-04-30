defmodule Hologram.Transpiler.ListTypeTransformer do
  alias Hologram.Transpiler.AST.ListType
  alias Hologram.Transpiler.Transformer

  def transform(ast, context) do
    data = Enum.map(ast, &Transformer.transform(&1, context))
    %ListType{data: data}
  end
end
