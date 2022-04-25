defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Transformer}

  alias Hologram.Compiler.IR.{
    AccessOperator,
    AdditionOperator,
    AliasDirective,
    AnonymousFunctionCall,
    AnonymousFunctionType,
    AtomType,
    BinaryType,
    Block,
    BooleanType,
    CaseExpression,
    ConsOperator,
    DivisionOperator,
    DotOperator,
    EqualToOperator,
    FloatType,
    FunctionDefinition,
    FunctionCall,
    IfExpression,
    ImportDirective,
    IntegerType,
    LessThanOperator,
    ListConcatenationOperator,
    ListSubtractionOperator,
    ListType,
    MacroDefinition,
    MapType,
    MatchOperator,
    MembershipOperator,
    ModuleDefinition,
    ModuleAttributeDefinition,
    ModuleAttributeOperator,
    ModulePseudoVariable,
    ModuleType,
    MultiplicationOperator,
    NilType,
    NotEqualToOperator,
    ProtocolDefinition,
    Quote,
    RelaxedBooleanAndOperator,
    RelaxedBooleanNotOperator,
    RelaxedBooleanOrOperator,
    RequireDirective,
    StrictBooleanAndOperator,
    StringType,
    StructType,
    SubtractionOperator,
    TupleType,
    TypeOperator,
    Typespec,
    UnaryNegativeOperator,
    UnaryPositiveOperator,
    Unquote,
    UseDirective,
    Variable
  }

  describe "operators" do
    test "access" do
      code = "a[:b]"
      ast = ast(code)

      assert %AccessOperator{} = Transformer.transform(ast, %Context{})
    end

    test "addition" do
      code = "1 + 2"
      ast = ast(code)

      assert %AdditionOperator{} = Transformer.transform(ast, %Context{})
    end

    test "cons" do
      code = "[h | t]"
      ast = ast(code)

      assert %ConsOperator{} = Transformer.transform(ast, %Context{})
    end

    test "division" do
      code = "1 / 2"
      ast = ast(code)

      assert %DivisionOperator{} = Transformer.transform(ast, %Context{})
    end

    test "dot" do
      code = "a.b"
      ast = ast(code)

      assert %DotOperator{} = Transformer.transform(ast, %Context{})
    end

    test "equal to" do
      code = "1 == 2"
      ast = ast(code)

      assert %EqualToOperator{} = Transformer.transform(ast, %Context{})
    end

    test "less than" do
      code = "1 < 2"
      ast = ast(code)

      assert %LessThanOperator{} = Transformer.transform(ast, %Context{})
    end

    test "list concatenation" do
      code = "[1, 2] ++ [3, 4]"
      ast = ast(code)

      assert %ListConcatenationOperator{} = Transformer.transform(ast, %Context{})
    end

    test "list subtraction" do
      code = "[1, 2] -- [3, 2]"
      ast = ast(code)

      assert %ListSubtractionOperator{} = Transformer.transform(ast, %Context{})
    end

    test "match" do
      code = "a = 1"
      ast = ast(code)

      assert %MatchOperator{} = Transformer.transform(ast, %Context{})
    end

    test "membership" do
      code = "1 in [1, 2]"
      ast = ast(code)

      assert %MembershipOperator{} = Transformer.transform(ast, %Context{})
    end

    test "module attribute" do
      code = "@a"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %ModuleAttributeOperator{name: :a}
    end

    test "multiplication" do
      code = "1 * 2"
      ast = ast(code)

      assert %MultiplicationOperator{} = Transformer.transform(ast, %Context{})
    end

    test "not equal to" do
      code = "1 != 2"
      ast = ast(code)

      assert %NotEqualToOperator{} = Transformer.transform(ast, %Context{})
    end

    test "pipe" do
      code = "100 |> div(2)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, %Context{})
    end

    test "relaxed boolean and" do
      code = "true && false"
      ast = ast(code)

      assert %RelaxedBooleanAndOperator{} = Transformer.transform(ast, %Context{})
    end

    test "relaxed boolean not, block AST" do
      code = "!false"
      ast = ast(code)

      assert %RelaxedBooleanNotOperator{} = Transformer.transform(ast, %Context{})
    end

    test "relaxed boolean not, non-block AST" do
      code = "true && !false"
      ast = ast(code)

      assert %RelaxedBooleanAndOperator{right: %RelaxedBooleanNotOperator{}} =
               Transformer.transform(ast, %Context{})
    end

    test "relaxed boolean or" do
      code = "true || false"
      ast = ast(code)

      assert %RelaxedBooleanOrOperator{} = Transformer.transform(ast, %Context{})
    end

    test "strict boolean and" do
      code = "true and false"
      ast = ast(code)

      assert %StrictBooleanAndOperator{} = Transformer.transform(ast, %Context{})
    end

    test "subtraction" do
      code = "1 - 2"
      ast = ast(code)

      assert %SubtractionOperator{} = Transformer.transform(ast, %Context{})
    end

    test "type" do
      code = "str::binary"
      ast = ast(code)

      assert %TypeOperator{} = Transformer.transform(ast, %Context{})
    end

    test "unary negative" do
      code = "-2"
      ast = ast(code)

      assert %UnaryNegativeOperator{} = Transformer.transform(ast, %Context{})
    end

    test "unary positive" do
      code = "+2"
      ast = ast(code)

      assert %UnaryPositiveOperator{} = Transformer.transform(ast, %Context{})
    end
  end

  describe "types" do
    test "anonymous function" do
      code = "fn -> 1 end"
      ast = ast(code)

      assert %AnonymousFunctionType{} = Transformer.transform(ast, %Context{})
    end

    test "atom" do
      code = ":test"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %AtomType{value: :test}
    end

    test "binary" do
      code = "<<1, 2>>"
      ast = ast(code)

      assert %BinaryType{} = Transformer.transform(ast, %Context{})
    end

    test "boolean" do
      code = "true"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %BooleanType{value: true}
    end

    test "float" do
      code = "1.0"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %FloatType{value: 1.0}
    end

    test "integer" do
      code = "1"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %IntegerType{value: 1}
    end

    test "list" do
      code = "[1, 2]"
      ast = ast(code)

      assert %ListType{} = Transformer.transform(ast, %Context{})
    end

    test "map" do
      code = "%{a: 1, b: 2}"
      ast = ast(code)

      assert %MapType{} = Transformer.transform(ast, %Context{})
    end

    test "module from module segments" do
      code = "Hologram.Compiler.TransformerTest"
      ast = ast(code)

      assert %ModuleType{} = Transformer.transform(ast, %Context{})
    end

    test "module from atom" do
      module = Hologram.Compiler.TransformerTest
      assert %ModuleType{} = Transformer.transform(module, %Context{})
    end

    test "nil" do
      code = "nil"
      ast = ast(code)

      assert %NilType{} = Transformer.transform(ast, %Context{})
    end

    test "string" do
      code = "\"test\""
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %StringType{value: "test"}
    end

    test "struct" do
      code = "%Hologram.Test.Fixtures.Compiler.Transformer.Module2{a: 1}"
      ast = ast(code)

      assert %StructType{} = Transformer.transform(ast, %Context{})
    end

    test "tuple, 2 elements" do
      code = "{1, 2}"
      ast = ast(code)

      assert %TupleType{} = Transformer.transform(ast, %Context{})
    end

    test "tuple, non-2 elements" do
      code = "{1, 2, 3}"
      ast = ast(code)

      assert %TupleType{} = Transformer.transform(ast, %Context{})
    end

    test "nested" do
      code = "[1, {2, 3, 4}]"
      ast = ast(code)
      result = Transformer.transform(ast, %Context{})

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

  describe "definitions" do
    test "public function" do
      code = "def test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast, %Context{})
    end

    test "private function" do
      code = "defp test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast, %Context{})
    end

    test "macro" do
      code = """
      defmacro test_macro(a, b) do
        quote do
          1
        end
      end
      """

      ast = ast(code)

      assert %MacroDefinition{} = Transformer.transform(ast, %Context{})
    end

    test "module" do
      code = "defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do end"
      ast = ast(code)

      assert %ModuleDefinition{} = Transformer.transform(ast, %Context{})
    end

    test "module attribute" do
      code = "@a 1"
      ast = ast(code)

      assert %ModuleAttributeDefinition{} = Transformer.transform(ast, %Context{})
    end

    test "protocol" do
      code = """
      defprotocol Hologram.Test.Fixtures.PlaceholderModule1 do
        def test_fun(a, b)
      end
      """

      ast = ast(code)

      assert %ProtocolDefinition{} = Transformer.transform(ast, %Context{})
    end
  end

  describe "directives" do
    test "alias" do
      code = "alias Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %AliasDirective{} = Transformer.transform(ast, %Context{})
    end

    test "import" do
      code = "import Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %ImportDirective{} = Transformer.transform(ast, %Context{})
    end

    test "require" do
      code = "require Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %RequireDirective{} = Transformer.transform(ast, %Context{})
    end

    test "use" do
      code = "use Hologram.Compiler.TransformerTest"
      ast = ast(code)

      assert %UseDirective{} = Transformer.transform(ast, %Context{})
    end
  end

  describe "control flow" do
    test "anonymous function call" do
      code = "test.(123)"
      ast = ast(code)

      assert %AnonymousFunctionCall{} = Transformer.transform(ast, %Context{})
    end

    test "case expression" do
      code = """
      case x do
        %{a: a} -> :ok
        2 -> :error
      end
      """

      ast = ast(code)

      assert %CaseExpression{} = Transformer.transform(ast, %Context{})
    end

    test "for expression" do
      code = "for n <- [1, 2], do: n * n"
      ast = ast(code)

      assert %FunctionCall{module: Enum, function: :reduce} = Transformer.transform(ast, %Context{})
    end

    test "function called without a module" do
      code = "test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, %Context{})
    end

    test "function called on module" do
      code = "Hologram.Compiler.TransformerTest.test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, %Context{})
    end

    test "if expression" do
      code = "if true, do: 1, else: 2"
      ast = ast(code)

      assert %IfExpression{} = Transformer.transform(ast, %Context{})
    end
  end

  describe "other" do
    test "block" do
      ast = {:__block__, [], [1, 2]}
      assert %Block{} = Transformer.transform(ast, %Context{})
    end

    test "quote" do
      code = "quote do 1 end"
      ast = ast(code)

      assert %Quote{} = Transformer.transform(ast, %Context{})
    end

    test "typespec" do
      code = "@spec test_fun(atom()) :: list(integer())"
      ast = ast(code)

      assert %Typespec{} = Transformer.transform(ast, %Context{})
    end

    test "unquote" do
      code = "unquote(abc)"
      ast = ast(code)

      assert %Unquote{} = Transformer.transform(ast, %Context{})
    end

    test "__MODULE__ macro" do
      code = "__MODULE__"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %ModulePseudoVariable{}
    end

    test "variable, last AST tuple elem is nil" do
      code = "a"
      ast = ast(code)

      result = Transformer.transform(ast, %Context{})
      assert result == %Variable{name: :a}
    end

    test "variable, last AST tuple elem is module" do
      ast = {:a, [line: 1], Hologram.Compiler.TransformerTest}

      result = Transformer.transform(ast, %Context{})
      assert result == %Variable{name: :a}
    end
  end
end
