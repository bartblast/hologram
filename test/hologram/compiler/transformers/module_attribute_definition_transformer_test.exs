defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ModuleAttributeDefinitionTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeDefinition, NotSupportedExpression}

  test "module attribute" do
    code = "@abc 1 + 2"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})
    expected = %ModuleAttributeDefinition{name: :abc, value: %IntegerType{value: 3}}

    assert result == expected
  end

  test "behaviour callback spec" do
    code = "@callback some_fun :: any()"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})
    assert %NotSupportedExpression{type: :behaviour_callback_spec} = result
  end
end
