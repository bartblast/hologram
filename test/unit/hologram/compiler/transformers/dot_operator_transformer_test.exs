defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.DotOperatorTransformer
  alias Hologram.Compiler.IR.AccessOperator
  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.ModulePseudoVariable
  alias Hologram.Compiler.IR.Symbol

  test "access operator" do
    code = "a[:x]"
    ast = ast(code)

    assert %AccessOperator{} = DotOperatorTransformer.transform(ast, %Context{})
  end

  describe "anonymous function call" do
    test "without arguments" do
      code = "test.()"
      ast = ast(code)

      assert %AnonymousFunctionCall{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with arguments" do
      code = "test.(1, 2)"
      ast = ast(code)

      assert %AnonymousFunctionCall{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "dot operator on symbol" do
    test "without parenthesis" do
      code = "a.x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast, %Context{})

      expected = %DotOperator{
        left: %Symbol{name: :a},
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = "a.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with parenthesis, with arguments" do
      code = "a.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "dot operator on alias" do
    test "without parenthesis" do
      code = "Abc.x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast, %Context{})

      expected = %DotOperator{
        left: %Alias{segments: [:Abc]},
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = "Abc.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with parenthesis, with arguments" do
      code = "Abc.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "dot operator on module attribute" do
    test "without parenthesis" do
      code = "@abc.x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast, %Context{})

      expected = %DotOperator{
        left: %ModuleAttributeOperator{name: :abc},
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = "@abc.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with parenthesis, with arguments" do
      code = "@abc.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "dot operator on expression" do
    test "without parenthesis" do
      code = "(3 + 4).x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast, %Context{})

      expected = %DotOperator{
        left: %AdditionOperator{
          left: %IntegerType{value: 3},
          right: %IntegerType{value: 4}
        },
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = "(3 + 4).x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with parenthesis, with arguments" do
      code = "(3 + 4).x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "dot operator on __MODULE__ pseudo-variable" do
    test "without parenthesis" do
      code = "__MODULE__.x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast, %Context{})

      expected = %DotOperator{
        left: %ModulePseudoVariable{},
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = "__MODULE__.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with parenthesis, with arguments" do
      code = "__MODULE__.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "Erlang function call" do
    test "without parenthesis" do
      code = ":my_module.x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast, %Context{})

      expected = %DotOperator{
        left: %AtomType{value: :my_module},
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = ":my_module.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end

    test "with parenthesis, with arguments" do
      code = ":my_module.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  test "string interpolation" do
    code = ~S("#{test}")
    {_, _, [{_, _, [ast, _]}]} = ast(code)

    assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
  end
end
