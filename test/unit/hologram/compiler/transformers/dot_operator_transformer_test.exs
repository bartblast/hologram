defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.DotOperatorTransformer
  alias Hologram.Compiler.IR.AccessOperator
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.Symbol

  test "access operator" do
    code = "a[:x]"
    ast = ast(code)

    assert %AccessOperator{} = DotOperatorTransformer.transform(ast, %Context{})
  end

  test "anonymous function call" do
    code = "test.()"
    ast = ast(code)

    assert %AnonymousFunctionCall{} = DotOperatorTransformer.transform(ast, %Context{})
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

    test "with parenthesis" do
      code = "a.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end

  describe "dot operator on module" do
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

    test "with parenthesis" do
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

    test "with parenthesis" do
      code = "@abc.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast, %Context{})
    end
  end
end
