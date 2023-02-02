defmodule Hologram.Compiler.TypeOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{TypeOperator, Variable}
  alias Hologram.Compiler.TypeOperatorTransformer

  test "transform/2" do
    code = "str::binary"
    ast = ast(code)

    result = TypeOperatorTransformer.transform(ast)

    expected = %TypeOperator{
      left: %Variable{name: :str},
      right: :binary
    }

    assert result == expected
  end
end
