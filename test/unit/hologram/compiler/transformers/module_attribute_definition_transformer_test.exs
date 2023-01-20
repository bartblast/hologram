defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.ModuleAttributeDefinition
  alias Hologram.Compiler.IR.NotSupportedExpression
  alias Hologram.Compiler.ModuleAttributeDefinitionTransformer

  test "regular value" do
    code = "@abc 1 + 2"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})

    expected = %ModuleAttributeDefinition{
      name: :abc,
      ast: {:+, [line: 1], [1, 2]}
    }

    assert result == expected
  end

  test "behaviour callback spec" do
    code = "@callback some_fun :: any()"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})

    expected_ast =
      {:@, [line: 1],
       [
         {:callback, [line: 1],
          [{:"::", [line: 1], [{:some_fun, [line: 1], nil}, {:any, [line: 1], []}]}]}
       ]}

    expected = %NotSupportedExpression{type: :behaviour_callback_spec, ast: expected_ast}

    assert result == expected
  end
end
