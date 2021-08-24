defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.{ModuleAttributeDefinition, NotSupportedExpression}

  def transform({:@, _, [{:callback, _, _}]} = ast, %Context{}) do
    %NotSupportedExpression{ast: ast, type: :behaviour_callback_spec}
  end

  def transform({:@, _, [{name, _, [ast]}]}, %Context{} = context) do
    {value, _} = Code.eval_quoted(ast)

    %ModuleAttributeDefinition{
      name: name,
      value: Transformer.transform(value, context)
    }
  end
end
