defmodule Hologram.Transpiler.MapTypeTransformer do
  alias Hologram.Transpiler.AST.MapType
  alias Hologram.Transpiler.Transformer

  def transform(ast, module, imports, aliases) do
    data =
      Enum.map(ast, fn {key, value} ->
        {
          Transformer.transform(key, module, imports, aliases),
          Transformer.transform(value, module, imports, aliases)
        }
      end)

    %MapType{data: data}
  end
end
