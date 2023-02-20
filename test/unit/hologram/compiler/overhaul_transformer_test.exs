defmodule Hologram.Compiler.OverhaulTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR.{
    Call,
    IntegerType,
    TupleType,
    TypeOperator
  }

  describe "data types" do
    test "nested" do
      code = "[1, {2, 3, 4}]"
      ast = ast(code)
      result = Transformer.transform(ast)

      expected = %ListType{
        data: [
          %IntegerType{value: 1},
          %TupleType{
            data: [
              %IntegerType{value: 2},
              %IntegerType{value: 3},
              %IntegerType{value: 4}
            ]
          }
        ]
      }

      assert result == expected
    end
  end

  describe "control flow" do
    test "simple call" do
      code = "test(123)"
      ast = ast(code)

      assert %Call{} = Transformer.transform(ast)
    end

    test "call on alias" do
      code = "Abc.test(123)"
      ast = ast(code)

      assert %Call{} = Transformer.transform(ast)
    end

    test "contextual call" do
      ast = {:test_fun, [context: A.B, imports: [{0, C.D}]], A.B}
      assert %Call{} = Transformer.transform(ast)
    end

    test "for expression" do
      code = "for n <- [1, 2], do: n * n"
      ast = ast(code)

      assert %Call{module: %Alias{segments: [:Enum]}, function: :reduce} =
               Transformer.transform(ast)
    end
  end
end
