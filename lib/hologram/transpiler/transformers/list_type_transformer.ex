defmodule Hologram.Transpiler.ListTypeTransformer do
  alias Hologram.Transpiler.AST.ListType
  alias Hologram.Transpiler.Transformer

  def transform(ast, module, imports, aliases) do
    data = Enum.map(ast, &Transformer.transform(&1, module, imports, aliases))
    %ListType{data: data}
  end
end
