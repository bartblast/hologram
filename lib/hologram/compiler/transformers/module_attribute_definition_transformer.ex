defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.ModuleAttributeDefinition

  def transform(name, ast, %Context{} = context) do
    %ModuleAttributeDefinition{
      name: name,
      value: Transformer.transform(ast, context)
    }
  end
end
