defmodule Hologram.Compiler.FunctionCallTransformerTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{FunctionCall, IntegerType, NotSupportedExpression, Variable}
  alias Hologram.Compiler.{Context, FunctionCallTransformer}

  test "function without args called on module" do
    code = "Hologram.Compiler.FunctionCallTransformerTest.test()"
    ast = ast(code)

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      function: :test,
      params: []
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function with args called on module" do
    code = "Hologram.Compiler.FunctionCallTransformerTest.test(1, 2)"
    ast = ast(code)

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      function: :test,
      params: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function without args called without module" do
    code = "test()"
    ast = ast(code)

    expected = %FunctionCall{
      module: Kernel,
      function: :test,
      params: []
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function with args called without module" do
    code = "test(1, 2)"
    ast = ast(code)

    expected = %FunctionCall{
      module: Kernel,
      function: :test,
      params: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "string interpolation" do
    code = ~S("#{test}")
    {_, _, [{_, _, [ast, _]}]} = ast(code)

    expected = %FunctionCall{
      module: Kernel,
      function: :to_string,
      params: [%Variable{name: :test}]
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function call on __MODULE__ macro result" do
    code = "__MODULE__.test(1, 2)"
    ast = ast(code)
    context = %Context{module: Hologram.Test.Fixtures.PlaceholderModule}

    result = FunctionCallTransformer.transform(ast, context)

    expected = %FunctionCall{
      function: :test,
      module: Hologram.Test.Fixtures.PlaceholderModule,
      params: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "Erlang function call" do
    code = ":timer.sleep(1_000)"
    ast = ast(code)

    result = FunctionCallTransformer.transform(ast, %Context{})
    expected = %NotSupportedExpression{ast: ast, type: :erlang_function_call}

    assert result == expected
  end
end
