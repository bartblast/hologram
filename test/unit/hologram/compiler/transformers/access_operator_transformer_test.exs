defmodule Hologram.Compiler.AccessOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AccessOperatorTransformer
  alias Hologram.Compiler.IR.{AccessOperator, AtomType, IntegerType, MapType, Variable}

  test "data is variable" do
    code = "a[:b]"
    ast = ast(code)

    result = AccessOperatorTransformer.transform(ast)
    expected = %AccessOperator{data: %Variable{name: :a}, key: %AtomType{value: :b}}

    assert result == expected
  end

  test "data is explicit value" do
    code = "%{a: 1, b: 2}[:b]"
    ast = ast(code)

    result = AccessOperatorTransformer.transform(ast)

    expected = %AccessOperator{
      data: %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      },
      key: %AtomType{value: :b}
    }

    assert result == expected
  end
end
