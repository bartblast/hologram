defmodule Hologram.Compiler.TransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{
    AdditionOperator,
    Alias,
    AtomType,
    BinaryType,
    BooleanType,
    DotOperator,
    FunctionDefinition,
    FunctionCall,
    Import,
    IntegerType,
    ListType,
    MapType,
    MatchOperator,
    ModuleDefinition,
    ModuleAttributeDefinition,
    ModuleAttributeOperator,
    NotSupportedExpression,
    StringType,
    StructType,
    TupleType,
    TypeOperator,
    UseDirective,
    Variable
  }

  alias Hologram.Compiler.{Context, Transformer}

  @context %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

  describe "types" do
    test "atom" do
      code = ":test"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %AtomType{value: :test}
    end

    test "binary" do
      code = "<<1, 2>>"
      ast = ast(code)

      assert %BinaryType{} = Transformer.transform(ast, @context)
    end

    test "boolean" do
      code = "true"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %BooleanType{value: true}
    end

    test "integer" do
      code = "1"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %IntegerType{value: 1}
    end

    test "list" do
      code = "[1, 2]"
      ast = ast(code)

      assert %ListType{} = Transformer.transform(ast, @context)
    end

    test "map" do
      code = "%{a: 1, b: 2}"
      ast = ast(code)

      assert %MapType{} = Transformer.transform(ast, @context)
    end

    test "string" do
      code = "\"test\""
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %StringType{value: "test"}
    end

    test "struct" do
      code = "%Hologram.Test.Fixtures.Compiler.Transformer.Module2{a: 1}"
      ast = ast(code)

      assert %StructType{} = Transformer.transform(ast, @context)
    end

    test "tuple, 2 elements" do
      code = "{1, 2}"
      ast = ast(code)

      assert %TupleType{} = Transformer.transform(ast, @context)
    end

    test "tuple, non-2 elements" do
      code = "{1, 2, 3}"
      ast = ast(code)

      assert %TupleType{} = Transformer.transform(ast, @context)
    end

    test "nested" do
      code = "[1, {2, 3, 4}]"
      ast = ast(code)
      result = Transformer.transform(ast, @context)

      expected =
        %ListType{
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
    test "addition" do
      code = "1 + 2"
      ast = ast(code)

      assert %AdditionOperator{} = Transformer.transform(ast, @context)
    end

    test "dot" do
      code = "a.b"
      ast = ast(code)

      assert %DotOperator{} = Transformer.transform(ast, @context)
    end

    test "match" do
      code = "a = 1"
      ast = ast(code)

      assert %MatchOperator{} = Transformer.transform(ast, @context)
    end

    test "module attribute" do
      code = "@a"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %ModuleAttributeOperator{name: :a}
    end

    test "type" do
      code = "str::binary"
      ast = ast(code)

      assert %TypeOperator{} = Transformer.transform(ast, @context)
    end
  end

  describe "definitions" do
    test "function" do
      code = "def test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast, @context)
    end

    test "module" do
      code = "defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do end"
      ast = ast(code)

      assert %ModuleDefinition{} = Transformer.transform(ast, @context)
    end

    test "module attribute" do
      code = "@a 1"
      ast = ast(code)

      assert %ModuleAttributeDefinition{} = Transformer.transform(ast, @context)
    end
  end

  describe "directives" do
    test "alias" do
      code = "alias Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %Alias{} = Transformer.transform(ast, @context)
    end

    test "import" do
      code = "import Hologram.Test.Fixtures.Compiler.Transformer.Module1"
      ast = ast(code)

      assert %Import{} = Transformer.transform(ast, @context)
    end

    test "use" do
      code = "use Hologram.Compiler.TransformerTest"
      ast = ast(code)

      assert %UseDirective{} = Transformer.transform(ast, @context)
    end
  end

  describe "other" do
    test "local function call" do
      code = "test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, @context)
    end

    test "aliased module function call" do
      code = "Hologram.Compiler.TransformerTest.test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, @context)
    end

    test "string interpolation" do
      code = "\"\#{sth}\""
      ast = ast(code)

      result = Transformer.transform(ast, @context)

      expected =
        %BinaryType{
          parts: [
            %TypeOperator{
              left: %FunctionCall{
                function: :to_string,
                module: Kernel,
                params: [%Variable{name: :sth}]
              },
              right: :binary
            }
          ]
        }

      assert result == expected
    end

    test "variable" do
      code = "a"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %Variable{name: :a}
    end
  end

  describe "not supported" do
    test "Erlang function call" do
      code = ":timer.sleep(1_000)"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      expected = %NotSupportedExpression{ast: ast, type: :erlang_function_call}

      assert result == expected
    end
  end
end
