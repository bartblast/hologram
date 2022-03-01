defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ModuleAttributeDefinitionTransformer}

  alias Hologram.Compiler.IR.{
    IntegerType,
    ModuleAttributeDefinition,
    NotSupportedExpression,
    TupleType
  }

  def test_fun do
    {1, 2, 3, 4}
  end

  test "hardcoded value" do
    code = "@abc 1"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})
    expected = %ModuleAttributeDefinition{name: :abc, value: %IntegerType{value: 1}}

    assert result == expected
  end

  test "expression" do
    code = "@abc 1 + 2"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})
    expected = %ModuleAttributeDefinition{name: :abc, value: %IntegerType{value: 3}}

    assert result == expected
  end

  test "function call" do
    code = "@abc Hologram.Compiler.ModuleAttributeDefinitionTransformerTest.test_fun()"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})

    expected = %ModuleAttributeDefinition{
      name: :abc,
      value: %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2},
          %IntegerType{value: 3},
          %IntegerType{value: 4}
        ]
      }
    }

    assert result == expected
  end

  test "behaviour callback spec" do
    code = "@callback some_fun :: any()"
    ast = ast(code)

    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})
    assert %NotSupportedExpression{type: :behaviour_callback_spec} = result
  end
end
