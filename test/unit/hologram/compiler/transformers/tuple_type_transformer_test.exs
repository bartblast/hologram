defmodule Hologram.Compiler.TupleTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Compiler.TupleTypeTransformer

  describe "transform/2" do
    test "2-element tuple" do
      code = "{1, 2}"
      ast = ast(code)

      result = TupleTypeTransformer.transform(ast)

      expected = %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }

      assert result == expected
    end

    test "non-2-element tuple" do
      code = "{1, 2, 3}"
      ast = ast(code)

      result = TupleTypeTransformer.transform(ast)

      expected = %TupleType{
        data: [
          %IntegerType{value: 1},
          %IntegerType{value: 2},
          %IntegerType{value: 3}
        ]
      }

      assert result == expected
    end
  end
end
