defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR.{ModuleAttributeDefinition, NotSupportedExpression}

  def transform({:@, _, [{:callback, _, _}]} = ast, %Context{}) do
    %NotSupportedExpression{ast: ast, type: :behaviour_callback_spec}
  end

  def transform({:@, _, [{name, _, [ast]}]}, %Context{} = context) do
    %ModuleAttributeDefinition{
      name: name,
      ast: ast,
      expression: Transformer.transform(ast, context)
    }
  end
end
