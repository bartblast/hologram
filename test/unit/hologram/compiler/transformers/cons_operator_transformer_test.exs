defmodule Hologram.Compiler.ConsOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ConsOperatorTransformer}
  alias Hologram.Compiler.IR.{ConsOperator, ListType, Variable}

  test "transform/3" do
    code = "h | t"
    ast = ast(code)

    result = ConsOperatorTransformer.transform(ast, %Context{})

    expected = %ConsOperator{
      head: %Variable{name: :h},
      tail: %Variable{name: :t}
    }

    assert result == expected
  end
end
