defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.{ModuleAttributeDefinition, NotSupportedExpression}

  def transform({:@, _, [{:callback, _, _}]} = ast, %Context{}) do
    %NotSupportedExpression{ast: ast, type: :behaviour_callback_spec}
  end

  def transform({:@, _, [{name, _, [ast]}]}, %Context{}) do
    %ModuleAttributeDefinition{
      name: name,
      ast: ast
    }
  end
end
