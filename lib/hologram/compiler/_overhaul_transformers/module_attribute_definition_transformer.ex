defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  def transform({:@, _, [{:callback, _, _}]} = ast) do
    %IR.NotSupportedExpression{type: :behaviour_callback_spec, ast: ast}
  end

  def transform({:@, _, [{name, _, [ast]}]}) do
    %IR.ModuleAttributeDefinition{
      name: name,
      expression: Transformer.transform(ast)
    }
  end
end
