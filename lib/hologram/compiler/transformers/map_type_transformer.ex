defmodule Hologram.Compiler.MapTypeTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.MapType

  def transform(ast, %Context{} = context) do
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
