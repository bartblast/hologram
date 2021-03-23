defmodule Holograf.Transpiler.GeneratorTest do
  use ExUnit.Case

  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{MapType, StructType}
  alias Holograf.Transpiler.AST.{Function, Module, Variable}
  alias Holograf.Transpiler.Generator

  describe "primitive types" do
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

    test "string" do
      result = Generator.generate(%StringType{value: "Test"})
      assert result == "{ type: 'string', value: 'Test' }"
    end
  end

  describe "data structures" do
    test "map, empty" do
      ast = %MapType{data: []}
      result = Generator.generate(ast)
      assert result == "{}"
    end

    test "map, not nested" do
      ast = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      result = Generator.generate(ast)

      assert result == "{ 'a': 1, 'b': 2 }"
    end

    test "map, nested" do
      ast = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {
            %AtomType{value: :b},
            %MapType{
              data: [
                {%AtomType{value: :c}, %IntegerType{value: 2}},
                {
                  %AtomType{value: :d},
                  %MapType{
                    data: [
                      {%AtomType{value: :e}, %IntegerType{value: 3}},
                      {%AtomType{value: :f}, %IntegerType{value: 4}}
                    ]
                  }
                }
              ]
            }
          }
        ]
      }

      result = Generator.generate(ast)

      assert result == "{ 'a': 1, 'b': { 'c': 2, 'd': { 'e': 3, 'f': 4 } } }"
    end

    test "struct, empty" do
      ast = %StructType{module: [:Abc, :Bcd], data: []}
      result = Generator.generate(ast)
      assert result == "{ __type__: 'struct', __module__: 'Abc.Bcd' }"
    end

    test "struct, not nested" do
      ast = %StructType{
        module: [:Abc, :Bcd],
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      result = Generator.generate(ast)

      assert result == "{ __type__: 'struct', __module__: 'Abc.Bcd', 'a': 1, 'b': 2 }"
    end

    test "struct, nested" do
      ast = %StructType{
        module: [:Abc, :Bcd],
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {
            %AtomType{value: :b},
            %StructType{
              module: [:Bcd, :Cde],
              data: [
                {%AtomType{value: :c}, %IntegerType{value: 2}},
                {
                  %AtomType{value: :d},
                  %StructType{
                    module: [:Cde, :Def],
                    data: [
                      {%AtomType{value: :e}, %IntegerType{value: 3}},
                      {%AtomType{value: :f}, %IntegerType{value: 4}}
                    ]
                  }
                }
              ]
            }
          }
        ]
      }

      result = Generator.generate(ast)

      assert result == "{ __type__: 'struct', __module__: 'Abc.Bcd', 'a': 1, 'b': { __type__: 'struct', __module__: 'Bcd.Cde', 'c': 2, 'd': { __type__: 'struct', __module__: 'Cde.Def', 'e': 3, 'f': 4 } } }"
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
          name: "Prefix.Test"
        }

      result = Generator.generate(ast)

      # TODO: update after function body generating is implemented
      expected = """
      class PrefixTest {

      static test_1() {
      if (patternMatchFunctionArgs([ { __type__: 'variable', __module__: 'Holograf.Transpiler.AST.Variable' } ], arguments)) {
      let a = arguments[0];
      return 1;
      }
      else if (patternMatchFunctionArgs([ { __type__: 'variable', __module__: 'Holograf.Transpiler.AST.Variable' }, { __type__: 'variable', __module__: 'Holograf.Transpiler.AST.Variable' } ], arguments)) {
      let a = arguments[0];
      let b = arguments[1];
      1;
      return 2;
      }
      }

      static test_2() {
      if (patternMatchFunctionArgs([ { __type__: 'variable', __module__: 'Holograf.Transpiler.AST.Variable' } ], arguments)) {
      let a = arguments[0];
      return 1;
      }
      }

      }
      """

      assert result == expected
    end

    test "variable" do
      result = Generator.generate(%Variable{name: :test})
      expected = "{ __type__: 'variable', __module__: 'Holograf.Transpiler.AST.Variable' }"
      assert result == expected
    end
  end
end
