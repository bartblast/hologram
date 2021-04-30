defmodule Hologram.Transpiler.StructTypeTransformer do
  alias Hologram.Transpiler.AST.StructType
  alias Hologram.Transpiler.Resolver
  alias Hologram.Transpiler.Transformer

  def transform(ast, struct_module, context) do
    resolved_module =
      case Resolver.resolve_aliased_module(struct_module, context[:aliases]) do
        nil ->
          struct_module
        aliased_module ->
          aliased_module
      end

    data = Transformer.transform(ast, context).data

    %StructType{module: resolved_module, data: data}
  end
end
