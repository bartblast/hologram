defmodule Hologram.Transpiler.MapTypeTransformer do
  alias Hologram.Transpiler.AST.MapType
  alias Hologram.Transpiler.Transformer

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
