defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.ModuleAttributeDefinitionTransformer

  test "regular value" do
    code = "@abc 1 + 2"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast)

    expected = %IR.ModuleAttributeDefinition{
      name: :abc,
      expression: %IR.AdditionOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.IntegerType{value: 2}
      }
    }

    assert result == expected
  end
end
