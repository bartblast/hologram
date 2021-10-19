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
end
