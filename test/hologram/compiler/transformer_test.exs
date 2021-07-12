defmodule Hologram.Compiler.TransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{
    AdditionOperator,
    Alias,
    AtomType,
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
    StringType,
    StructType,
    TupleType,
    UseDirective,
    Variable
  }

  alias Hologram.Compiler.{Context, Transformer}

  @context %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

  describe "types" do
    test "atom" do
      code = ":test"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %AtomType{value: :test}
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

    test "string" do
      code = "\"test\""
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %StringType{value: "test"}
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

    test "struct" do
      code = "%Test{a: 1, b: 2}"
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
  end

  describe "definitions" do
    test "function" do
      code = "def test, do: :ok"
      ast = ast(code)

      assert %FunctionDefinition{} = Transformer.transform(ast, @context)
    end

    test "module" do
      code = "defmodule Test do end"
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
      code = "alias Abc.Bcd"
      ast = ast(code)

      assert %Alias{} = Transformer.transform(ast, @context)
    end

    test "import without 'only' clause" do
      code = "import Abc.Bcd"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %Import{module: [:Abc, :Bcd], only: []}
    end

    test "import with 'only' clause" do
      code = "import Abc.Bcd, only: [cde: 2]"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %Import{module: [:Abc, :Bcd], only: [cde: 2]}
    end

    test "use" do
      code = "use Abc.Bcd"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %UseDirective{module: [:Abc, :Bcd]}
    end
  end

  describe "other" do
    test "local function call" do
      code = "test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, @context)
    end

    test "aliased module function call" do
      code = "Abc.test(123)"
      ast = ast(code)

      assert %FunctionCall{} = Transformer.transform(ast, @context)
    end

    test "variable" do
      code = "a"
      ast = ast(code)

      result = Transformer.transform(ast, @context)
      assert result == %Variable{name: :a}
    end
  end
end
