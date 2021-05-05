defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{AtomType, DotOperator, Variable}
  alias Hologram.Compiler.DotOperatorTransformer

  test "transform/3" do
    # a.b
    left = {:a, [line: 1], nil}
    right = :b

    context = [module: [:Test], imports: [], aliases: []]
    result = DotOperatorTransformer.transform(left, right, context)

    expected =
      %DotOperator{
        left: %Variable{name: :a},
        right: %AtomType{value: :b}
      }

    assert result == expected
  end
end
