defmodule Hologram.Compiler.GeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.{AdditionOperator, AtomType, BooleanType, DotOperator, FunctionCall, IntegerType, MapType, ModuleAttributeOperator, ModuleDefinition, StringType, StructType, Variable}
  alias Hologram.Compiler.Generator

  describe "types" do
    test "atom" do
      result = Generator.generate(%AtomType{value: :test})
      assert result == "{ type: 'atom', value: 'test' }"
    end

    test "boolean" do
      result = Generator.generate(%BooleanType{value: true})
      assert result == "{ type: 'boolean', value: true }"
    end

    test "integer" do
      result = Generator.generate(%IntegerType{value: 123})
      assert result == "{ type: 'integer', value: 123 }"
    end

    test "map" do
      ast = %MapType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}]}

      result = Generator.generate(ast)

      expected =
        "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

      assert result == expected
    end

    test "string" do
      result = Generator.generate(%StringType{value: "Test"})
      assert result == "{ type: 'string', value: 'Test' }"
    end

    test "struct" do
      ast = %StructType{
        data: [{%AtomType{value: :a}, %IntegerType{value: 1}}],
        module: [:Abc, :Bcd]
      }

      result = Generator.generate(ast)

      expected =
        "{ type: 'struct', module: 'Abc.Bcd', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

      assert result == expected
    end
  end

  describe "operators" do
    test "addition" do
      ast =
        %AdditionOperator{
          left: %IntegerType{value: 1},
          right: %IntegerType{value: 2}
        }

      result = Generator.generate(ast)

      expected =
        "Kernel.$add({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

      assert result == expected
    end

    test "dot" do
      ast =
        %DotOperator{
          left: %Variable{name: :x},
          right: %AtomType{value: :a}
        }

      result = Generator.generate(ast)
      expected = "Kernel.$dot(x, { type: 'atom', value: 'a' })"

      assert result == expected
    end

    test "module attribute" do
      ast = %ModuleAttributeOperator{name: :x}

      result = Generator.generate(ast)
      expected = "$state.data['~atom[x]']"

      assert result == expected
    end
  end

  describe "definitions" do
    test "module" do
      ast =
        %ModuleDefinition{
          aliases: [],
          attributes: [],
          functions: [],
          imports: [],
          name: [:Test]
        }

      result = Generator.generate(ast)
      expected = "class Test {\n\n\n}\n"

      assert result == expected
    end
  end

  test "function call" do
    ast =
      %FunctionCall{
        function: :abc,
        module: [:Test],
        params: [%IntegerType{value: 1}]
      }

    result = Generator.generate(ast)
    expected = "Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end

  describe "variable" do
    test "boxed" do
      result = Generator.generate(%Variable{name: :test}, [], boxed: true)
      expected = "{ type: 'variable', name: 'test' }"

      assert result == expected
    end

    test "not boxed" do
      result = Generator.generate(%Variable{name: :test})
      expected = "test"

      assert result == expected
    end
  end
end
