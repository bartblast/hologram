defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.FunctionCall
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeDefinition
  alias Hologram.Compiler.IR.NotSupportedExpression
  alias Hologram.Compiler.ModuleAttributeDefinitionTransformer

  test "hardcoded value" do
    code = "@abc 1"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})

    expected = %ModuleAttributeDefinition{
      name: :abc,
      ast: 1,
      expression: %IntegerType{value: 1},
      value: nil
    }

    assert result == expected
  end

  test "expression" do
    code = "@abc 1 + 2"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})

    expected = %ModuleAttributeDefinition{
      name: :abc,
      ast: {:+, [line: 1], [1, 2]},
      expression: %AdditionOperator{
        left: %IntegerType{value: 1},
        right: %IntegerType{value: 2}
      },
      value: nil
    }

    assert result == expected
  end

  test "function call" do
    code = "@xyz Abc.Bcd.test_fun()"
    ast = ast(code)
    result = ModuleAttributeDefinitionTransformer.transform(ast, %Context{})

    expected_ast =
      {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc, :Bcd]}, :test_fun]}, [line: 1], []}

    expected = %ModuleAttributeDefinition{
      name: :xyz,
      ast: expected_ast,
      expression: %FunctionCall{
        args: [],
        function: :test_fun,
        module: Abc.Bcd,
        module_alias: Abc.Bcd
      },
      value: nil
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
