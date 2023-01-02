defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.DotOperatorTransformer
  alias Hologram.Compiler.IR.AccessOperator
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.IR.Symbol

  test "access operator" do
    code = "a[:b]"
    ast = ast(code)

    assert %AccessOperator{} = DotOperatorTransformer.transform(ast, %Context{})
  end

  test "anonymous function call" do
    code = "test.()"
    ast = ast(code)

    assert %AnonymousFunctionCall{} = DotOperatorTransformer.transform(ast, %Context{})
  end

  test "dot operator on symbol, without parenthesis" do
    code = "a.b"
    ast = ast(code)
    result = DotOperatorTransformer.transform(ast, %Context{})

    expected = %DotOperator{
      left: %Symbol{name: :a},
      right: %AtomType{value: :b}
    }

    assert result == expected
  end

  # test "test" do
  #   code = "my_fun()"
  #   ast = ast(code)
  #   IO.inspect(ast)
  # end

  # test "transform/3" do
  #   code = "a.b"
  #   ast = ast(code)

  #   result = DotOperatorTransformer.transform(ast, %Context{})

  #   expected = %DotOperator{
  #     left: %Variable{name: :a},
  #     right: %AtomType{value: :b}
  #   }

  #   assert result == expected
  # end
end
