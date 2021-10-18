defmodule Hologram.Compiler.GeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Generator, Opts}

  alias Hologram.Compiler.IR.{
    AdditionOperator,
    AtomType,
    BinaryType,
    BooleanType,
    DotOperator,
    FunctionCall,
    IntegerType,
    ListType,
    MapType,
    ModuleAttributeDefinition,
    ModuleAttributeOperator,
    ModuleDefinition,
    ModuleType,
    StringType,
    StructType,
    TupleType,
    TypeOperator,
    Variable
  }

  describe "types" do
    test "binary" do
      ir = %BinaryType{
        parts: [
          %StringType{value: "abc"},
          %StringType{value: "xyz"}
        ]
      }

      result = Generator.generate(ir, %Context{}, %Opts{})

      expected =
        "{ type: 'binary', data: [ { type: 'string', value: 'abc' }, { type: 'string', value: 'xyz' } ] }"

      assert result == expected
    end

    test "boolean" do
      ir = %BooleanType{value: true}
      result = Generator.generate(ir, %Context{}, %Opts{})
      assert result == "{ type: 'boolean', value: true }"
    end

    test "integer" do
      ir = %IntegerType{value: 123}
      result = Generator.generate(ir, %Context{}, %Opts{})
      assert result == "{ type: 'integer', value: 123 }"
    end

    test "list" do
      ir = %ListType{data: [%IntegerType{value: 123}]}
      result = Generator.generate(ir, %Context{}, %Opts{})
      assert result == "{ type: 'list', data: [ { type: 'integer', value: 123 } ] }"
    end

    test "map" do
      ir = %MapType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}]}

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

      assert result == expected
    end

    test "module" do
      ir = %ModuleType{module: Abc.Bcd}

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "{ type: 'module', className: 'Elixir_Abc_Bcd' }"

      assert result == expected
    end

    test "struct" do
      ir = %StructType{
        data: [{%AtomType{value: :a}, %IntegerType{value: 1}}],
        module: Abc.Bcd
      }

      result = Generator.generate(ir, %Context{}, %Opts{})

      expected =
        "{ type: 'struct', module: 'Elixir_Abc_Bcd', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

      assert result == expected
    end

    test "tuple" do
      ir = %TupleType{data: []}

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "{ type: 'tuple', data: [] }"

      assert result == expected
    end

    test "nested" do
      ir = %ListType{
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

      result = Generator.generate(ir, %Context{}, %Opts{})

      expected =
        "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'tuple', data: [ { type: 'integer', value: 2 }, { type: 'integer', value: 3 }, { type: 'integer', value: 4 } ] } ] }"

      assert result == expected
    end
  end

  describe "operators" do
    test "addition" do
      ir = %AdditionOperator{
        left: %IntegerType{value: 1},
        right: %IntegerType{value: 2}
      }

      result = Generator.generate(ir, %Context{}, %Opts{})

      expected =
        "Elixir_Kernel.$add({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

      assert result == expected
    end

    test "dot" do
      ir = %DotOperator{
        left: %Variable{name: :x},
        right: %AtomType{value: :a}
      }

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "Elixir_Kernel_SpecialForms.$dot(x, { type: 'atom', value: 'a' })"

      assert result == expected
    end

    test "module attribute" do
      ir = %ModuleAttributeOperator{name: :x}
      context = %Context{module: Hologram.Compiler.GeneratorTest}

      result = Generator.generate(ir, context, %Opts{})
      expected = "Elixir_Hologram_Compiler_GeneratorTest.$x"

      assert result == expected
    end

    test "type" do
      ir = %TypeOperator{
        left: %IntegerType{value: 1},
        right: :binary
      }

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "Elixir_Kernel_SpecialForms.$type({ type: 'integer', value: 1 }, 'binary')"

      assert result == expected
    end
  end

  describe "definitions" do
    test "module" do
      ir = %ModuleDefinition{
        attributes: [
          %ModuleAttributeDefinition{
            name: :abc,
            value: %IntegerType{value: 123}
          }
        ],
        module: Hologram.Test.Fixtures.PlaceholderModule
      }

      result = Generator.generate(ir, %Context{}, %Opts{})

      expected = """
      window.Elixir_Hologram_Test_Fixtures_PlaceholderModule = class Elixir_Hologram_Test_Fixtures_PlaceholderModule {

      static $abc = { type: 'integer', value: 123 };
      }
      """

      assert result == expected
    end
  end

  describe "other" do
    test "sigil_H" do
      ir = %FunctionCall{
        function: :sigil_H,
        module: Hologram.Runtime.Commons,
        params: [
          %BinaryType{
            parts: [
              %StringType{value: "test"}
            ]
          },
          %ListType{data: []}
        ]
      }

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "[ { type: 'text', content: 'test' } ]"

      assert result == expected
    end

    test "function call" do
      ir = %FunctionCall{
        function: :abc,
        module: Test,
        params: [%IntegerType{value: 1}]
      }

      result = Generator.generate(ir, %Context{}, %Opts{})
      expected = "Elixir_Test.abc({ type: 'integer', value: 1 })"

      assert result == expected
    end
  end
end
