defmodule Hologram.Compiler.MapTypeTransformer do
  alias Hologram.Compiler.IR.MapType
  alias Hologram.Compiler.Transformer

  def transform({:%{}, _, data}) do
    data =
      Enum.map(data, fn {key, value} ->
        {
          Transformer.transform(key),
          Transformer.transform(value)
        }
      end)

    %MapType{data: data}
  end
end
