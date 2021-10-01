defmodule Hologram.Compiler.TypeOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, TypeOperatorTransformer}
  alias Hologram.Compiler.IR.{TypeOperator, Variable}

  test "transform/2" do
    code = "str::binary"
    {:"::", _, ast} = ast(code)

    result = TypeOperatorTransformer.transform(ast, %Context{})

    expected = %TypeOperator{
      left: %Variable{name: :str},
      right: :binary
    }

    assert result == expected
  end
end
