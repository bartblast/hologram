defmodule Hologram.Compiler.TransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.{AdditionOperator, Alias, AtomType, BooleanType, DotOperator, FunctionDefinition, FunctionCall, Import, IntegerType, ListType, MapType, MatchOperator, Module, ModuleAttributeDef, ModuleAttributeOperator, StringType, StructType, Variable}
  alias Hologram.Compiler.Transformer

  describe "types" do
    test "atom" do
      code = ":test"
      ast = ast(code)

      assert Transformer.transform(ast) == %AtomType{value: :test}
    end

    test "boolean" do
      code = "true"
      ast = ast(code)

      assert Transformer.transform(ast) == %BooleanType{value: true}
    end

    test "integer" do
      code = "1"
      ast = ast(code)

      assert Transformer.transform(ast) == %IntegerType{value: 1}
    end

    test "string" do
      code = "\"test\""
      ast = ast(code)

      assert Transformer.transform(ast) == %StringType{value: "test"}
    end

    test "list" do
      code = "[1, 2]"
      ast = ast(code)

      assert %ListType{} = Transformer.transform(ast)
    end

    test "map" do
      code = "%{a: 1, b: 2}"
      ast = ast(code)

      assert %MapType{} = Transformer.transform(ast)
    end

    test "struct" do
      code = "%Test{a: 1, b: 2}"
      ast = ast(code)

      assert %StructType{} = Transformer.transform(ast)
    end
  end

  describe "operators" do
    test "addition" do
      code = "1 + 2"
      ast = ast(code)

      assert %AdditionOperator{} = Transformer.transform(ast)
    end

    test "dot" do
      code = "a.b"
      ast = ast(code)

      assert %DotOperator{} = Transformer.transform(ast)
    end

    test "match" do
      code = "a = 1"
      ast = ast(code)

      assert %MatchOperator{} = Transformer.transform(ast)
    end

    test "module attribute" do
      code = "@a"
      ast = ast(code)

      assert Transformer.transform(ast) == %ModuleAttributeOperator{name: :a}
    end
  end

  describe "definitions" do
    test "function" do
      code = "def test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast)
    end

    test "module" do
      code = "defmodule Test do end"
      ast = ast(code)

      assert %Module{} = Transformer.transform(ast)
    end

    test "module attribute" do
      code = "@a 1"
      ast = ast(code)

      assert %ModuleAttributeDef{} = Transformer.transform(ast)
    end
  end

  describe "directives" do
    test "alias" do
      code = "alias Abc.Bcd"
      ast = ast(code)

      assert %Alias{} = Transformer.transform(ast)
    end

    test "import" do
      code = "import Abc.Bcd"
      ast = ast(code)

      assert Transformer.transform(ast) == %Import{module: [:Abc, :Bcd]}
    end
  end

  describe "other" do
    test "local function call" do
      code = "test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast)
    end

    test "aliased module function call" do
      code = "Abc.test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast)
    end

    test "variable" do
      code = "a"
      ast = ast(code)

      assert Transformer.transform(ast) == %Variable{name: :a}
    end
  end
end
