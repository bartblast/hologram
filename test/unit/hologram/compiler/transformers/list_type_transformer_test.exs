defmodule Hologram.Compiler.ListTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ListType}
  alias Hologram.Compiler.ListTypeTransformer

  test "transform/2" do
    code = "[1, 2]"
    ast = ast(code)

    result = ListTypeTransformer.transform(ast)

    expected = %ListType{
      data: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end
end
