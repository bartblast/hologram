defmodule Holograf.Transpiler.GeneratorTest do
  use ExUnit.Case

  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{MapType, StructType}
  alias Holograf.Transpiler.AST.{Call, Function, Module, Variable}
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
      assert result == "{ type: 'map', data: {} }"
    end

    test "map, not nested" do
      ast = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      result = Generator.generate(ast)
      expected = "{ type: 'map', data: { '~Holograf.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Holograf.Transpiler.AST.AtomType[b]': { type: 'integer', value: 2 } } }"

      assert result == expected
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
      expected = "{ type: 'map', data: { '~Holograf.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Holograf.Transpiler.AST.AtomType[b]': { type: 'map', data: { '~Holograf.Transpiler.AST.AtomType[c]': { type: 'integer', value: 2 }, '~Holograf.Transpiler.AST.AtomType[d]': { type: 'map', data: { '~Holograf.Transpiler.AST.AtomType[e]': { type: 'integer', value: 3 }, '~Holograf.Transpiler.AST.AtomType[f]': { type: 'integer', value: 4 } } } } } } }"

      assert result == expected
    end

    test "struct, empty" do
      ast = %StructType{module: [:Abc, :Bcd], data: []}
      result = Generator.generate(ast)
      assert result == "{ type: 'struct', module: 'Abc.Bcd', data: {} }"
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
      expected = "{ type: 'struct', module: 'Abc.Bcd', data: { '~Holograf.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Holograf.Transpiler.AST.AtomType[b]': { type: 'integer', value: 2 } } }"

      assert result == expected
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
      expected = "{ type: 'struct', module: 'Abc.Bcd', data: { '~Holograf.Transpiler.AST.AtomType[a]': { type: 'integer', value: 1 }, '~Holograf.Transpiler.AST.AtomType[b]': { type: 'struct', module: 'Bcd.Cde', data: { '~Holograf.Transpiler.AST.AtomType[c]': { type: 'integer', value: 2 }, '~Holograf.Transpiler.AST.AtomType[d]': { type: 'struct', module: 'Cde.Def', data: { '~Holograf.Transpiler.AST.AtomType[e]': { type: 'integer', value: 3 }, '~Holograf.Transpiler.AST.AtomType[f]': { type: 'integer', value: 4 } } } } } } }"

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
      if (Holograf.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else if (Holograf.patternMatchFunctionArgs([ { type: 'variable' }, { type: 'variable' } ], arguments)) {
      let a = arguments[0];
      let b = arguments[1];
      { type: 'integer', value: 1 };
      return { type: 'integer', value: 2 };
      }
      }

      static test_2() {
      if (Holograf.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
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
