defmodule Hologram.Compiler.StructTypeTransformer do
  alias Hologram.Compiler.IR.StructType
  alias Hologram.Compiler.{Resolver, Transformer}

  def transform(ast, struct_module, context) do
    resolved_module = Resolver.resolve(struct_module, context[:aliases])
    data = Transformer.transform(ast, context).data

    %StructType{module: resolved_module, data: data}
  end
end
