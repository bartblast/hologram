defmodule Hologram.Compiler.OverhaulTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR.{
    Call,
    CaseExpression,
    IfExpression,
    IntegerType,
    RequireDirective,
    TupleType,
    TypeOperator,
    UseDirective
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

  describe "directives" do
    test "require" do
      code = "require Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %RequireDirective{} = Transformer.transform(ast)
    end

    test "use" do
      code = "use Hologram.Compiler.TransformerTest"
      ast = ast(code)

      assert %UseDirective{} = Transformer.transform(ast)
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

    test "case expression" do
      code = """
      case x do
        %{a: a} -> :ok
        2 -> :error
      end
      """

      ast = ast(code)

      assert %CaseExpression{} = Transformer.transform(ast)
    end

    test "for expression" do
      code = "for n <- [1, 2], do: n * n"
      ast = ast(code)

      assert %Call{module: %Alias{segments: [:Enum]}, function: :reduce} =
               Transformer.transform(ast)
    end

    test "if expression" do
      code = "if true, do: 1, else: 2"
      ast = ast(code)

      assert %IfExpression{} = Transformer.transform(ast)
    end
  end
end
