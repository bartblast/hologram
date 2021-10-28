defmodule Hologram.Compiler.TupleTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, TupleTypeTransformer}
  alias Hologram.Compiler.IR.{IntegerType, TupleType}

  @context %Context{module: Abc}

  describe "transform/2" do
    test "2-element tuple" do
      code = "{1, 2}"
      ast = ast(code)

      result = TupleTypeTransformer.transform(ast, @context)

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

      result = TupleTypeTransformer.transform(ast, @context)

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
