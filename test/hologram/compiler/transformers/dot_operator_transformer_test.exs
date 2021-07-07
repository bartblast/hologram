defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, DotOperator, Variable}
  alias Hologram.Compiler.DotOperatorTransformer

  test "transform/3" do
    code = "a.b"
    {{:., _, [left, right]}, _, []} = ast(code)

    context = [module: [:Test], imports: [], aliases: []]
    result = DotOperatorTransformer.transform(left, right, context)

    expected = %DotOperator{
      left: %Variable{name: :a},
      right: %AtomType{value: :b}
    }

    assert result == expected
  end
end
