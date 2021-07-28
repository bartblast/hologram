defmodule Hologram.Compiler.TupleTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, TupleTypeTransformer}
  alias Hologram.Compiler.IR.{IntegerType, TupleType}

  @context %Context{
    module: Abc,
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "transform/2" do
    code = "{1, 2}"
    ast = ast(code)

    result = TupleTypeTransformer.transform(ast, @context)

    expected =
      %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

    assert result == expected
  end
end
