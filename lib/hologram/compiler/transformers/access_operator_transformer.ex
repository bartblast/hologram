defmodule Hologram.Compiler.AccessOperatorTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.AccessOperator
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [Access, :get]}, _, [data, key]}, %Context{} = context) do
    data = Transformer.transform(data, context)
    key = Transformer.transform(key, context)

    %AccessOperator{data: data, key: key}
  end
end
