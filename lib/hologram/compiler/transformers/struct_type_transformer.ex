defmodule Hologram.Compiler.StructTypeTransformer do
  alias Hologram.Compiler.{Context, Resolver, Transformer}
  alias Hologram.Compiler.IR.StructType

  def transform(ast, module_segs, %Context{} = context) do
    module = Resolver.resolve(module_segs, context.aliases)
    data = Transformer.transform(ast, context).data

    %StructType{module: module, data: data}
  end
end
