defmodule Hologram.Transpiler.ModuleAttributeDefTransformer do
  alias Hologram.Transpiler.AST.ModuleAttributeDef
  alias Hologram.Transpiler.Transformer

  def transform(name, ast, context) do
    %ModuleAttributeDef{
      name: name,
      value: Transformer.transform(ast, context)
    }
  end
end
