defmodule Hologram.Compiler.FunctionCallTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, FunctionCallTransformer}

  alias Hologram.Compiler.IR.{
    AliasDirective,
    AtomType,
    FunctionCall,
    IntegerType,
    ListType,
    ModuleAttributeOperator,
    NotSupportedExpression,
    Variable
  }

  test "function without params called on non-aliased module" do
    code = "Hologram.Compiler.FunctionCallTransformerTest.test()"
    ast = ast(code)

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      module_alias: Hologram.Compiler.FunctionCallTransformerTest,
      function: :test,
      args: []
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function with params called on non-aliased module" do
    code = "Hologram.Compiler.FunctionCallTransformerTest.test(1, 2)"
    ast = ast(code)

    expected = %FunctionCall{
      module: Hologram.Compiler.FunctionCallTransformerTest,
      module_alias: Hologram.Compiler.FunctionCallTransformerTest,
      function: :test,
      args: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function without params called without module" do
    code = "make_ref()"
    ast = ast(code)

    expected = %FunctionCall{
      module: Kernel,
      module_alias: nil,
      function: :make_ref,
      args: []
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function with params called without module" do
    code = "max(1, 2)"
    ast = ast(code)

    expected = %FunctionCall{
      module: Kernel,
      module_alias: nil,
      function: :max,
      args: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    result = FunctionCallTransformer.transform(ast, %Context{})
    assert result == expected
  end

  test "function without params called on aliased module" do
    code = "Xyz.test()"
    ast = ast(code)
    aliases = [%AliasDirective{module: Abc.Bcd, as: [:Xyz]}]
    context = %Context{aliases: aliases}

    result = FunctionCallTransformer.transform(ast, context)

    expected = %FunctionCall{
      module: Abc.Bcd,
      module_alias: Xyz,
      function: :test,
      args: []
    }

    assert result == expected
  end

  test "function with params called on aliased module" do
    code = "Xyz.test(1, 2)"
    ast = ast(code)
    aliases = [%AliasDirective{module: Abc.Bcd, as: [:Xyz]}]
    context = %Context{aliases: aliases}

    result = FunctionCallTransformer.transform(ast, context)

    expected = %FunctionCall{
      module: Abc.Bcd,
      module_alias: Xyz,
      function: :test,
      args: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  describe "Kernel.to_string/1" do
    test "called without module" do
      code = "to_string(test)"
      ast = ast(code)

      result = FunctionCallTransformer.transform(ast, %Context{})

      expected = %FunctionCall{
        module: Kernel,
        module_alias: nil,
        function: :to_string,
        args: [%Variable{name: :test}]
      }

      assert result == expected
    end

    test "called with module" do
      code = "Kernel.to_string(test)"
      ast = ast(code)

      result = FunctionCallTransformer.transform(ast, %Context{})

      expected = %FunctionCall{
        module: Kernel,
        module_alias: Kernel,
        function: :to_string,
        args: [%Variable{name: :test}]
      }

      assert result == expected
    end

    test "string interpolation" do
      code = ~S("#{test}")
      {_, _, [{_, _, [ast, _]}]} = ast(code)

      expected = %FunctionCall{
        module: Kernel,
        module_alias: nil,
        function: :to_string,
        args: [%Variable{name: :test}]
      }

      result = FunctionCallTransformer.transform(ast, %Context{})
      assert result == expected
    end
  end

  test "function call on __MODULE__ macro result" do
    code = "__MODULE__.test(1, 2)"
    ast = ast(code)
    context = %Context{module: Hologram.Test.Fixtures.PlaceholderModule1}

    result = FunctionCallTransformer.transform(ast, context)

    expected = %FunctionCall{
      function: :test,
      module: Hologram.Test.Fixtures.PlaceholderModule1,
      module_alias: Hologram.Test.Fixtures.PlaceholderModule1,
      args: [
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

  test "function called on expression" do
    code = "@test.abc(1, 2)"
    ast = ast(code)

    result = FunctionCallTransformer.transform(ast, %Context{})

    expected = %FunctionCall{
      function: :apply,
      module: Kernel,
      module_alias: nil,
      args: [
        %ModuleAttributeOperator{name: :test},
        %AtomType{value: :abc},
        %ListType{
          data: [
            %IntegerType{value: 1},
            %IntegerType{value: 2}
          ]
        }
      ]
    }

    assert result == expected
  end
end
