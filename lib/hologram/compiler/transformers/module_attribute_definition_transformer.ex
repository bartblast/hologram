defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  def transform({:@, _, [{:callback, _, _}]} = ast, %Context{}) do
    %IR.NotSupportedExpression{type: :behaviour_callback_spec, ast: ast}
  end

  def transform({:@, _, [{name, _, [ast]}]}, %Context{} = context) do
    %IR.ModuleAttributeDefinition{
      name: name,
      expression: Transformer.transform(ast, context)
    }
  end
end
