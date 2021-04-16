defmodule Hologram.Transpiler.GeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Transpiler.AST.{MapType, StructType}
  alias Hologram.Transpiler.AST.{Call, Function, Module, Variable}
  alias Hologram.Transpiler.Generator

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
      expected = "{ type: 'map', data: { '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 } } }"

      assert result == expected
    end

    test "string" do
      result = Generator.generate(%StringType{value: "Test"})
      assert result == "{ type: 'string', value: 'Test' }"
    end

    test "struct" do
      ast = %StructType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}], module: [:Abc, :Bcd]}

      result = Generator.generate(ast)
      expected = "{ type: 'struct', module: 'Abc.Bcd', data: { '~Hologram.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 } } }"

      assert result == expected
    end
  end

  describe "other" do
    # TODO: test modules with 0 and 1 functions;
    # TODO: test aliases

    test "module, multiple functions with multiple variants" do
      ast =
        %Module{
          aliases: [],
          functions: [
            %Function{
              bindings: [
                [%Variable{name: :a}]
              ],
              body: [
                %IntegerType{value: 1}
              ],
              name: :test_1,
              params: [
                %Variable{name: :a}
              ]
            },
            %Function{
              bindings: [
                [%Variable{name: :a}],
                [%Variable{name: :b}]
              ],
              body: [
                %IntegerType{value: 1},
                %IntegerType{value: 2}
              ],
              name: :test_1,
              params: [
                %Variable{name: :a},
                %Variable{name: :b}
              ]
            },
            %Function{
              bindings: [
                [%Variable{name: :a}]
              ],
              body: [
                %IntegerType{value: 1}
              ],
              name: :test_2,
              params: [
                %Variable{name: :a}
              ]
            }
          ],
          name: [:Prefix, :Test]
        }

      result = Generator.generate(ast)

      # TODO: update after function body generating is implemented
      expected = """
      class PrefixTest {

      static test_1() {
      if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else if (Hologram.patternMatchFunctionArgs([ { type: 'variable' }, { type: 'variable' } ], arguments)) {
      let a = arguments[0];
      let b = arguments[1];
      { type: 'integer', value: 1 };
      return { type: 'integer', value: 2 };
      }
      else {
        throw 'No match for the function call'
      }
      }

      static test_2() {
      if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else {
        throw 'No match for the function call'
      }
      }

      }
      """

      assert result == expected
    end

    test "variable" do
      result = Generator.generate(%Variable{name: :test})
      expected = "{ type: 'variable' }"
      assert result == expected
    end

    test "function call with params" do
      ast = %Call{
        module: [:Abc, :Bcd],
        function: :test,
        params: [
          %IntegerType{value: 1},
          %Variable{name: :xyz}
        ]
      }

      result = Generator.generate(ast)
      expected = "AbcBcd.test({ type: 'integer', value: 1 }, xyz)"

      assert result == expected
    end

    test "function call without params" do
      ast = %Call{
        module: [:Abc, :Bcd],
        function: :test,
        params: []
      }

      result = Generator.generate(ast)
      expected = "AbcBcd.test()"

      assert result == expected
    end
  end
end
