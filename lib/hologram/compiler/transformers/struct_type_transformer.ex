defmodule Hologram.Compiler.StructTypeTransformer do
  alias Hologram.Compiler.{Context, Resolver, Transformer}
  alias Hologram.Compiler.IR.StructType

  def transform({:%, _, [{_, _, module_segs}, data]}, %Context{} = context) do
    module = Resolver.resolve(module_segs, context)
    data = Transformer.transform(data, context).data

    %StructType{module: module, data: data}
  end
end
