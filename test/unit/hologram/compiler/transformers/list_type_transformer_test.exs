defmodule Hologram.Compiler.ListTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ListTypeTransformer}
  alias Hologram.Compiler.IR.{ConsOperator, IntegerType, ListType, Variable}

  @context %Context{module: Abc}

  test "regular list" do
    code = "[1, 2]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, @context)

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "cons operator" do
    code = "[h | t]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, @context)

    expected = %ListType{
      data: %ConsOperator{
        head: %Variable{name: :h},
        tail: %Variable{name: :t}
      }
    }

    assert result == expected
  end
end
