defmodule Hologram.Compiler.OverhaulTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR.{
    AliasDirective,
    AnonymousFunctionCall,
    BinaryType,
    Call,
    CaseExpression,
    DotOperator,
    FunctionDefinition,
    IfExpression,
    ImportDirective,
    IntegerType,
    ListConcatenationOperator,
    ListSubtractionOperator,
    ListType,
    MembershipOperator,
    ModuleDefinition,
    ModuleAttributeDefinition,
    ModuleAttributeOperator,
    MultiplicationOperator,
    NotEqualToOperator,
    ProtocolDefinition,
    Quote,
    RelaxedBooleanAndOperator,
    RelaxedBooleanNotOperator,
    RelaxedBooleanOrOperator,
    RequireDirective,
    StrictBooleanAndOperator,
    SubtractionOperator,
    TupleType,
    TypeOperator,
    Typespec,
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

    test "list" do
      code = "[1, 2]"
      ast = ast(code)

      assert %ListType{} = Transformer.transform(ast)
    end

    test "tuple, 2 elements" do
      code = "{1, 2}"
      ast = ast(code)

      assert %TupleType{} = Transformer.transform(ast)
    end

    test "tuple, non-2 elements" do
      code = "{1, 2, 3}"
      ast = ast(code)

      assert %TupleType{} = Transformer.transform(ast)
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
    test "dot" do
      code = "a.b"
      ast = ast(code)

      assert %DotOperator{} = Transformer.transform(ast)
    end

    test "list concatenation" do
      code = "[1, 2] ++ [3, 4]"
      ast = ast(code)

      assert %ListConcatenationOperator{} = Transformer.transform(ast)
    end

    test "list subtraction" do
      code = "[1, 2] -- [3, 2]"
      ast = ast(code)

      assert %ListSubtractionOperator{} = Transformer.transform(ast)
    end

    test "membership" do
      code = "1 in [1, 2]"
      ast = ast(code)

      assert %MembershipOperator{} = Transformer.transform(ast)
    end

    test "module attribute" do
      code = "@a"
      ast = ast(code)

      result = Transformer.transform(ast)
      assert result == %ModuleAttributeOperator{name: :a}
    end

    test "multiplication" do
      code = "1 * 2"
      ast = ast(code)

      assert %MultiplicationOperator{} = Transformer.transform(ast)
    end

    test "not equal to" do
      code = "1 != 2"
      ast = ast(code)

      assert %NotEqualToOperator{} = Transformer.transform(ast)
    end

    test "pipe" do
      code = "100 |> div(2)"
      ast = ast(code)

      assert %Call{} = Transformer.transform(ast)
    end

    test "relaxed boolean and" do
      code = "true && false"
      ast = ast(code)

      assert %RelaxedBooleanAndOperator{} = Transformer.transform(ast)
    end

    test "relaxed boolean not, block AST" do
      code = "!false"
      ast = ast(code)

      assert %RelaxedBooleanNotOperator{} = Transformer.transform(ast)
    end

    test "relaxed boolean not, non-block AST" do
      code = "true && !false"
      ast = ast(code)

      assert %RelaxedBooleanAndOperator{right: %RelaxedBooleanNotOperator{}} =
               Transformer.transform(ast)
    end

    test "relaxed boolean or" do
      code = "true || false"
      ast = ast(code)

      assert %RelaxedBooleanOrOperator{} = Transformer.transform(ast)
    end

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
    test "anonymous function call" do
      code = "test.(1, 2)"
      ast = ast(code)
      assert %AnonymousFunctionCall{} = Transformer.transform(ast)
    end

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

  describe "pseudo-variables" do
    test "__ENV__" do
      code = "__ENV__"
      ast = ast(code)

      result = Transformer.transform(ast)
      assert result == %IR.EnvPseudoVariable{}
    end

    test "__MODULE__" do
      code = "__MODULE__"
      ast = ast(code)

      result = Transformer.transform(ast)
      assert result == %IR.ModulePseudoVariable{}
    end
  end

  describe "other" do
    test "quote" do
      code = "quote do 1 end"
      ast = ast(code)

      assert %Quote{} = Transformer.transform(ast)
    end

    test "typespec" do
      code = "@spec test_fun(atom()) :: list(integer())"
      ast = ast(code)

      assert %Typespec{} = Transformer.transform(ast)
    end

    test "unquote" do
      code = "unquote(abc)"
      ast = ast(code)

      assert %Unquote{} = Transformer.transform(ast)
    end
  end
end
