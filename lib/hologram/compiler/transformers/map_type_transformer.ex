defmodule Hologram.Compiler.MapTypeTransformer do
  alias Hologram.Compiler.AST.MapType
  alias Hologram.Compiler.Transformer

  def transform(ast, context) do
    data =
      Enum.map(ast, fn {key, value} ->
        {
          Transformer.transform(key, context),
          Transformer.transform(value, context)
        }
      end)

    %MapType{data: data}
  end
end
