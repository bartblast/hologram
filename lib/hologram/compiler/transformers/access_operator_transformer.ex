defmodule Hologram.Compiler.AccessOperatorTransformer do
  alias Hologram.Compiler.IR.AccessOperator
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [Access, :get]}, _, [data, key]}) do
    data = Transformer.transform(data)
    key = Transformer.transform(key)

    %AccessOperator{data: data, key: key}
  end
end
