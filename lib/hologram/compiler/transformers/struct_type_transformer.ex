defmodule Hologram.Compiler.StructTypeTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.StructType
  alias Hologram.Compiler.Transformer

  def transform({:%, _, [{_, _, alias_segs}, data]}, %Context{} = context) do
    data = Transformer.transform(data, context).data
    %StructType{alias_segs: alias_segs, module: nil, data: data}
  end
end
