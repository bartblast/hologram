defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.AST.ModuleAttributeDefinition
  alias Hologram.Compiler.Transformer

  def transform(name, ast, context) do
    %ModuleAttributeDefinition{
      name: name,
      value: Transformer.transform(ast, context)
    }
  end
end
