defmodule Hologram.Transpiler.DotOperatorTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, DotOperator, Variable}
  alias Hologram.Transpiler.DotOperatorTransformer

  test "transform/5" do
    left = {:a, [line: 1], nil}
    right = :b

    result = DotOperatorTransformer.transform(left, right, [:Test], [], [])

    expected =
      %DotOperator{
        left: %Variable{name: :a},
        right: %AtomType{value: :b}
      }

    assert result == expected
  end
end
