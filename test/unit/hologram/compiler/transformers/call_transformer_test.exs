defmodule Hologram.Compiler.CallTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CallTransformer
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.ModulePseudoVariable
  alias Hologram.Compiler.IR.Symbol

  describe "simple call" do
    test "without arguments" do
      code = "my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: nil,
        function: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with arguments" do
      code = "my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: nil,
        function: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "call on alias" do
    test "without arguments" do
      code = "Abc.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %Alias{segments: [:Abc]},
        function: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with arguments" do
      code = "Abc.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %Alias{segments: [:Abc]},
        function: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "call on module attribute" do
    test "without params" do
      code = "@my_attr.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %ModuleAttributeOperator{name: :my_attr},
        function: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "@my_attr.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %ModuleAttributeOperator{name: :my_attr},
        function: :my_fun,
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
      code = "(3 + 4).my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %AdditionOperator{
          left: %IntegerType{value: 3},
          right: %IntegerType{value: 4}
        },
        function: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "(3 + 4).my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %AdditionOperator{
          left: %IntegerType{value: 3},
          right: %IntegerType{value: 4}
        },
        function: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  describe "call on __MODULE__ pseudo-variable" do
    test "without params" do
      code = "__MODULE__.my_fun()"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %ModulePseudoVariable{},
        function: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = "__MODULE__.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %ModulePseudoVariable{},
        function: :my_fun,
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
        module: %AtomType{value: :my_module},
        function: :my_fun,
        args: []
      }

      assert result == expected
    end

    test "with params" do
      code = ":my_module.my_fun(1, 2)"
      ast = ast(code)
      result = CallTransformer.transform(ast, %Context{})

      expected = %Call{
        module: %AtomType{value: :my_module},
        function: :my_fun,
        args: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end
  end

  test "string interpolation" do
    code = ~S("#{test}")
    {_, _, [{_, _, [ast, _]}]} = ast(code)
    result = CallTransformer.transform(ast, %Context{})

    expected = %Call{
      module: %Alias{segments: [:Kernel]},
      function: :to_string,
      args: [%Symbol{name: :test}]
    }

    assert result == expected
  end
end
