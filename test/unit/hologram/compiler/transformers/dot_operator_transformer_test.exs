defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, DotOperatorTransformer}
  alias Hologram.Compiler.IR.{AtomType, DotOperator, Variable}

  test "transform/3" do
    code = "a.b"
    ast = ast(code)

    result = DotOperatorTransformer.transform(ast, %Context{})

    expected = %DotOperator{
      left: %Variable{name: :a},
      right: %AtomType{value: :b}
    }

    assert result == expected
  end
end
