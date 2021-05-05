defmodule Hologram.Compiler.ModuleAttributeDefTransformer do
  alias Hologram.Compiler.AST.ModuleAttributeDef
  alias Hologram.Compiler.Transformer

  def transform(name, ast, context) do
    %ModuleAttributeDef{
      name: name,
      value: Transformer.transform(ast, context)
    }
  end
end
