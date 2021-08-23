defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ModuleAttributeDefinitionTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeDefinition}

  test "transform/2" do
    code = "@abc 1 + 2"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})
    expected = %ModuleAttributeDefinition{name: :abc, value: %IntegerType{value: 3}}

    assert result == expected
  end
end
