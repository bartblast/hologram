defmodule Hologram.Compiler.CallTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CallTransformer
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.ModulePseudoVariable
  alias Hologram.Compiler.IR.Variable

  describe "non-aliased call" do
    test "without params" do
      code = "my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: [],
        module: nil,
        module_expression: nil,
        name: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: [],
        module: nil,
        module_expression: nil,
        name: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "aliased call" do
    test "without params" do
      code = "Abc.Bcd.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: [:Abc, :Bcd],
        module: nil,
        module_expression: nil,
        name: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "Abc.Bcd.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: [:Abc, :Bcd],
        module: nil,
        module_expression: nil,
        name: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "call on expression" do
    test "without params" do
      code = "@my_expr.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: nil,
        module: nil,
        module_expression: %ModuleAttributeOperator{name: :my_expr},
        name: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "@my_expr.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: nil,
        module: nil,
        module_expression: %ModuleAttributeOperator{name: :my_expr},
        name: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "call on __MODULE__ pseudo variable" do
    test "without params" do
      code = "__MODULE__.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: nil,
        module: nil,
        module_expression: %ModulePseudoVariable{},
        name: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "__MODULE__.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: nil,
        module: nil,
        module_expression: %ModulePseudoVariable{},
        name: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "Erlang function call" do
    test "without params" do
      code = ":my_module.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: nil,
        module: :"Erlang.MyModule",
        module_expression: nil,
        name: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = ":my_module.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        alias_segs: nil,
        module: :"Erlang.MyModule",
        module_expression: nil,
        name: :my_fun,
        args: [%IntegerType{value: 1}, %IntegerType{value: 2}]
      }

      assert result == expected
    end
  end

  test "string interpolation" do
    code = ~S("#{test}")
    {_, _, [{_, _, [ast, _]}]} = ast(code)
    result = CallTransformer.transform(ast, %Context{})

    expected = %Call{
      alias_segs: nil,
      module: Kernel,
      module_expression: nil,
      name: :to_string,
      args: [%Variable{name: :test}]
    }

    assert result == expected
  end
end
