defmodule Hologram.Compiler.BinaryTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, BinaryTypeTransformer}
  alias Hologram.Compiler.IR.{BinaryType, IntegerType}

  test "empty binary" do
    code = "<<>>"
    {:<<>>, _, parts} = ast(code)

    result = BinaryTypeTransformer.transform(parts, %Context{})
    expected = %BinaryType{parts: []}

    assert result == expected
  end

  test "non-empty binary" do
    code = "<<1, 2>>"
    {:<<>>, _, parts} = ast(code)

    result = BinaryTypeTransformer.transform(parts, %Context{})

    expected = %BinaryType{
      parts: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end
end
