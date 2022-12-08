defmodule Hologram.Compiler.AccessOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.AccessOperator

  def transform({{:., _, [Access, :get]}, _, [data, key]}, %Context{} = context) do
    data = Transformer.transform(data, context)
    key = Transformer.transform(key, context)
    %AccessOperator{data: data, key: key}
  end
end
