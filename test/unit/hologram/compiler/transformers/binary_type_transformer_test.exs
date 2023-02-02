defmodule Hologram.Compiler.BinaryTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.BinaryTypeTransformer
  alias Hologram.Compiler.IR.{BinaryType, IntegerType}

  test "empty binary" do
    code = "<<>>"
    ast = ast(code)

    result = BinaryTypeTransformer.transform(ast)
    expected = %BinaryType{parts: []}

    assert result == expected
  end

  test "non-empty binary" do
    code = "<<1, 2>>"
    ast = ast(code)

    result = BinaryTypeTransformer.transform(ast)

    expected = %BinaryType{
      parts: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end
end
