defmodule Hologram.Compiler.MapTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapType}
  alias Hologram.Compiler.MapTypeTransformer

  test "transform/2" do
    code = "%{a: 1, b: 2}"
    ast = ast(code)

    result = MapTypeTransformer.transform(ast)

    expected = %MapType{
      data: [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]
    }

    assert result == expected
  end
end
