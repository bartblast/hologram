defmodule Hologram.Compiler.JSEncoder.ModuleDefinitionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}

  alias Hologram.Compiler.IR

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    Block,
    FunctionDefinition,
    IntegerType,
    ModuleDefinition,
    ParamAccess,
    Variable
  }

  @module Abc.Bcd

  # this case is not possible, because such module would be pruned:
  # test "empty module"

  describe "functions" do
    test "not preceded by attributes section" do
      # code:
      #
      # defmodule Abc.Bcd do
      #   def test(a) do
      #     1
      #   end
      # end

      ir = %ModuleDefinition{
        module: @module,
        attributes: [],
        functions: [
          %FunctionDefinition{
            bindings: [
              %Binding{
                name: :a,
                access_path: [%ParamAccess{index: 0}]
              }
            ],
            body: %Block{
              expressions: [
                %IntegerType{value: 1}
              ]
            },
            name: :test,
            params: [
              %Variable{name: :a}
            ]
          }
        ]
      }

      result = JSEncoder.encode(ir, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static test() {
      if (Hologram.Interpreter.isFunctionArgsPatternMatched([ { type: 'placeholder' } ], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end

    test "preceded by attributes section" do
      # code:
      #
      # defmodule Abc.Bcd do
      #   @abc 123
      #
      #   def test(a) do
      #     1
      #   end
      # end

      ir = %ModuleDefinition{
        module: @module,
        attributes: [
          %ModuleAttributeDefinition{
            name: :abc,
            value: %IntegerType{value: 123}
          }
        ],
        functions: [
          %FunctionDefinition{
            bindings: [
              %Binding{
                name: :a,
                access_path: [%ParamAccess{index: 0}]
              }
            ],
            body: %Block{
              expressions: [
                %IntegerType{value: 1}
              ]
            },
            name: :test,
            params: [
              %Variable{name: :a}
            ]
          }
        ]
      }

      result = JSEncoder.encode(ir, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static $abc = { type: 'integer', value: 123 };

      static test() {
      if (Hologram.Interpreter.isFunctionArgsPatternMatched([ { type: 'placeholder' } ], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end
  end
end
