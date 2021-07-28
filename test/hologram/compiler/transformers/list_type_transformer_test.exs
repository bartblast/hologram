defmodule Hologram.Compiler.ListTypeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ListTypeTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ListType}

  @context %Context{
    module: Abc,
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "transform/2" do
    code = "[1, 2]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast, @context)

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end
end
