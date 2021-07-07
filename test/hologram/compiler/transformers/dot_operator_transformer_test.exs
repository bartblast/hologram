defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, DotOperatorTransformer}
  alias Hologram.Compiler.IR.{AtomType, DotOperator, Variable}

  test "transform/3" do
    code = "a.b"
    {{:., _, [left, right]}, _, []} = ast(code)

    context = %Context{module: [:Test], imports: [], aliases: []}
    result = DotOperatorTransformer.transform(left, right, context)

    expected = %DotOperator{
      left: %Variable{name: :a},
      right: %AtomType{value: :b}
    }

    assert result == expected
  end
end
