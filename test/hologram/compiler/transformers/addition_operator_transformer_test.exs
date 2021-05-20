defmodule Hologram.Compiler.AdditionOperatorTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AdditionOperatorTransformer
  alias Hologram.Compiler.IR.{AdditionOperator, IntegerType, Variable}

  test "transform/3" do
    code = "a + 2"
    {:+, _, [left, right]} = ast(code)

    context = [module: [:Test], imports: [], aliases: []]
    result = AdditionOperatorTransformer.transform(left, right, context)

    expected =
      %AdditionOperator{
        left: %Variable{name: :a},
        right: %IntegerType{value: 2}
      }

    assert result == expected
  end
end
