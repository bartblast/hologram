defmodule Hologram.Compiler.ListTypeTransformer do
  alias Hologram.Compiler.IR.ListType
  alias Hologram.Compiler.Transformer

  def transform(ast) do
    data = Enum.map(ast, &Transformer.transform/1)
    %ListType{data: data}
  end
end
