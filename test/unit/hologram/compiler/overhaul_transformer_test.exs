defmodule Hologram.Compiler.OverhaulTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR.{
    AliasDirective,
    BinaryType,
    Call,
    CaseExpression,
    FunctionDefinition,
    IfExpression,
    ImportDirective,
    IntegerType,
    ModuleDefinition,
    ModuleAttributeDefinition,
    ProtocolDefinition,
    Quote,
    RequireDirective,
    StrictBooleanAndOperator,
    SubtractionOperator,
    TupleType,
    TypeOperator,
    UnaryNegativeOperator,
    Unquote,
    UseDirective
  }

  describe "data types" do
    test "binary" do
      code = "<<1, 2>>"
      ast = ast(code)

      assert %BinaryType{} = Transformer.transform(ast)
    end

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

  describe "operators" do
    test "strict boolean and" do
      code = "true and false"
      ast = ast(code)

      assert %StrictBooleanAndOperator{} = Transformer.transform(ast)
    end

    test "subtraction" do
      code = "1 - 2"
      ast = ast(code)

      assert %SubtractionOperator{} = Transformer.transform(ast)
    end

    test "type" do
      code = "str::binary"
      ast = ast(code)

      assert %TypeOperator{} = Transformer.transform(ast)
    end

    test "unary negative" do
      code = "-2"
      ast = ast(code)

      assert %UnaryNegativeOperator{} = Transformer.transform(ast)
    end
  end

  describe "definitions" do
    test "public function" do
      code = "def test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast)
    end

    test "private function" do
      code = "defp test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast)
    end

    test "module" do
      code = "defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do end"
      ast = ast(code)

      assert %ModuleDefinition{} = Transformer.transform(ast)
    end

    test "module attribute" do
      code = "@a 1"
      ast = ast(code)

      assert %ModuleAttributeDefinition{} = Transformer.transform(ast)
    end

    test "protocol" do
      code = """
      defprotocol Hologram.Test.Fixtures.PlaceholderModule1 do
        def test_fun(a, b)
      end
      """

      ast = ast(code)

      assert %ProtocolDefinition{} = Transformer.transform(ast)
    end
  end

  describe "directives" do
    test "alias" do
      code = "alias Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %AliasDirective{} = Transformer.transform(ast)
    end

    test "import" do
      code = "import Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %ImportDirective{} = Transformer.transform(ast)
    end

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

  describe "other" do
    test "quote" do
      code = "quote do 1 end"
      ast = ast(code)

      assert %Quote{} = Transformer.transform(ast)
    end

    test "unquote" do
      code = "unquote(abc)"
      ast = ast(code)

      assert %Unquote{} = Transformer.transform(ast)
    end
  end
end
