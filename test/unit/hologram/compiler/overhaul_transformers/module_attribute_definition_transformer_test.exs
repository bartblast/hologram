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

  test "behaviour callback spec" do
    code = "@callback some_fun :: any()"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast)

    expected_ast =
      {:@, [line: 1],
       [
         {:callback, [line: 1],
          [{:"::", [line: 1], [{:some_fun, [line: 1], nil}, {:any, [line: 1], []}]}]}
       ]}

    expected = %IR.NotSupportedExpression{type: :behaviour_callback_spec, ast: expected_ast}

    assert result == expected
  end
end
