defmodule Hologram.Compiler.StructTypeTransformer do
  alias Hologram.Compiler.AST.StructType
  alias Hologram.Compiler.{Resolver, Transformer}

  def transform(ast, struct_module, context) do
    resolved_module =
      case Resolver.resolve(struct_module, context[:aliases]) do
        nil ->
          struct_module
          
        aliased_module ->
          aliased_module
      end

    data = Transformer.transform(ast, context).data

    %StructType{module: resolved_module, data: data}
  end
end
