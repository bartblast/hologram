defmodule Holograf.Transpiler.GeneratorTest do
  use ExUnit.Case

  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{MapType, StructType}
  alias Holograf.Transpiler.AST.{Function, Module, Variable}
  alias Holograf.Transpiler.Generator

  describe "primitives" do
    test "atom" do
      result = Generator.generate(%AtomType{value: :test})
      assert result == "'test'"
    end

    test "boolean" do
      result = Generator.generate(%BooleanType{value: true})
      assert result == "true"
    end

    test "integer" do
      result = Generator.generate(%IntegerType{value: 123})
      assert result == "123"
    end

    test "string" do
      result = Generator.generate(%StringType{value: "Test"})
      assert result == "'Test'"
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
              args: [
                %Variable{name: :a}
              ],
              body: [
                %IntegerType{value: 1}
              ],
              name: :test_1
            },
            %Function{
              args: [
                %Variable{name: :a},
                %Variable{name: :b}
              ],
              body: [
                %IntegerType{value: 1},
                %IntegerType{value: 2}
              ],
              name: :test_1
            },
            %Function{
              args: [
                %Variable{name: :a}
              ],
              body: [
                %IntegerType{value: 1}
              ],
              name: :test_2
            }
          ],
          name: "Prefix.Test"
        }

      result = Generator.generate(ast)

      # TODO: update after function body generating is implemented
      expected = """
        class PrefixTest {
          static test_1() {}
          static test_2() {}
        }
        """

      assert result == expected
    end
  end
end
