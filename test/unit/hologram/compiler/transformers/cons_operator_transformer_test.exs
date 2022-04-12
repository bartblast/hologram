defmodule Hologram.Compiler.ConsOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{ConsOperatorTransformer, Context}
  alias Hologram.Compiler.IR.{ConsOperator, Variable}

  test "transform/2" do
    code = "[h | t]"
    ast = ast(code)

    result = ConsOperatorTransformer.transform(ast, %Context{})

    expected = %ConsOperator{
      head: %Variable{name: :h},
      tail: %Variable{name: :t}
    }

    assert result == expected
  end
end
