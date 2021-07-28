defmodule Hologram.Compiler.MapTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, MapTypeTransformer}
  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapType}

  @context %Context{
    module: Abc,
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "transform/2" do
    code = "%{a: 1, b: 2}"
    {:%{}, _, ast} = ast(code)

    result = MapTypeTransformer.transform(ast, @context)

    expected = %MapType{
      data: [
        {%AtomType{value: :a}, %IntegerType{value: 1}},
        {%AtomType{value: :b}, %IntegerType{value: 2}}
      ]
    }

    assert result == expected
  end
end
