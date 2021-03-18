# TODO: refactor
defmodule Holofograf.TranspilerTest do
  use ExUnit.Case

  alias Holofograf.Transpiler
  alias Holofograf.Transpiler.Atom
  alias Holofograf.Transpiler.Boolean
  alias Holofograf.Transpiler.Function
  alias Holofograf.Transpiler.Integer
  alias Holofograf.Transpiler.MapAccess
  alias Holofograf.Transpiler.MapType
  alias Holofograf.Transpiler.MatchOperator
  alias Holofograf.Transpiler.Module
  alias Holofograf.Transpiler.StringType
  alias Holofograf.Transpiler.Variable

  test "aggregate_functions/1" do
    module =
      %Module{
        body: [
          %Function{
            args: [
              %Variable{name: :a},
              %Variable{name: :b}
            ],
            body: [
              %Integer{value: 1},
              %Integer{value: 2}
            ],
            name: :test_1
          },
          %Atom{value: :non_function},
          %Function{
            args: [
              %Variable{name: :a},
              %Variable{name: :b},
              %Variable{name: :c}
            ],
            body: [
              %Integer{value: 1},
              %Integer{value: 2},
              %Integer{value: 3}
            ],
            name: :test_1
          },
          %Atom{value: :non_function},
          %Function{
            args: [
              %Variable{name: :a},
              %Variable{name: :b}
            ],
            body: [
              %Integer{value: 1},
              %Integer{value: 2}
            ],
            name: :test_2
          },
        ],
        name: "Prefix.Test"
      }

    result = Transpiler.aggregate_functions(module)

    expected = %{
      test_1: [
        %Function{
          args: [
            %Variable{name: :a},
            %Variable{name: :b}
          ],
          body: [
            %Integer{value: 1},
            %Integer{value: 2}
          ],
          name: :test_1
        },
        %Function{
          args: [
            %Variable{name: :a},
            %Variable{name: :b},
            %Variable{name: :c}
          ],
          body: [
            %Integer{value: 1},
            %Integer{value: 2},
            %Integer{value: 3}
          ],
          name: :test_1
        }
      ],
      test_2: [
        %Function{
          args: [
            %Variable{name: :a},
            %Variable{name: :b}
          ],
          body: [
            %Integer{value: 1},
            %Integer{value: 2}
          ],
          name: :test_2
        }
      ]
    }

    assert result == expected
  end

  describe "parse_file/1" do
    test "valid code" do
      assert {:ok, _} = Transpiler.parse_file("lib/demo/holograf/transpiler.ex")
    end

    test "invalid code" do
      assert {:error, _} = Transpiler.parse_file("README.md")
    end
  end

  describe "primitives transform/1" do
    test "atom" do
      ast = Transpiler.parse!(":test")
      assert Transpiler.transform(ast) == %Atom{value: :test}
    end

    test "boolean" do
      ast = Transpiler.parse!("true")
      assert Transpiler.transform(ast) == %Boolean{value: true}
    end

    test "integer" do
      ast = Transpiler.parse!("1")
      assert Transpiler.transform(ast) == %Integer{value: 1}
    end

    test "string" do
      ast = Transpiler.parse!("\"test\"")
      assert Transpiler.transform(ast) == %StringType{value: "test"}
    end
  end

  describe "data structures transform/1" do
    test "map, not nested" do
      ast = Transpiler.parse!("%{a: 1, b: 2}")
      result = Transpiler.transform(ast)

      expected = %MapType{
        data: [
          {%Atom{value: :a}, %Integer{value: 1}},
          {%Atom{value: :b}, %Integer{value: 2}}
        ]
      }

      assert result == expected
    end

    test "map, nested" do
      result =
        Transpiler.parse!("%{a: 1, b: %{c: 2, d: %{e: 3, f: 4}}}")
        |> Transpiler.transform()

      expected = %MapType{
        data: [
          {%Atom{value: :a}, %Integer{value: 1}},
          {%Atom{value: :b}, %MapType{
            data: [
              {%Atom{value: :c}, %Integer{value: 2}},
              {%Atom{value: :d}, %MapType{
                data: [
                  {%Atom{value: :e}, %Integer{value: 3}},
                  {%Atom{value: :f}, %Integer{value: 4}},
                ]
              }}
            ]
          }}
        ]
      }

      assert result == expected
    end
  end

  describe "operators transform/1" do
    test "match operator, simple" do
      result =
        Transpiler.parse!("x = 1")
        |> Transpiler.transform()


      expected = %MatchOperator{
        bindings: [[%Variable{name: :x}]],
        left: %Variable{name: :x},
        right: %Integer{value: 1}
      }

      assert result == expected
    end

    test "match operator, map with root keys" do
      result =
        Transpiler.parse!("%{a: x, b: y} = %{a: 1, b: 2}")
        |> Transpiler.transform()

      expected =
        %MatchOperator{
          bindings: [
            [
              %Variable{name: :x},
              %MapAccess{key: %Atom{value: :a}}
            ],
            [
              %Variable{name: :y},
              %MapAccess{key: %Atom{value: :b}}
            ]
          ],
          left: %MapType{
            data: [
              {%Atom{value: :a}, %Variable{name: :x}},
              {%Atom{value: :b}, %Variable{name: :y}}
            ]
          },
          right: %MapType{
            data: [
              {%Atom{value: :a}, %Integer{value: 1}},
              {%Atom{value: :b}, %Integer{value: 2}}
            ]
          }
        }

      assert result == expected
    end

    test "match operator, map with nested keys" do
      result =
        Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}} = %{a: 1, b: %{p: 9, r: 4}, c: 3, d: %{m: 0, n: 8}}")
        |> Transpiler.transform()

      expected =
        %MatchOperator{
          bindings: [
            [
              %Variable{name: :x},
              %MapAccess{key: %Atom{value: :b}},
              %MapAccess{key: %Atom{value: :p}}
            ],
            [
              %Variable{name: :y},
              %MapAccess{key: %Atom{value: :d}},
              %MapAccess{key: %Atom{value: :n}}
            ]
          ],
          left: %MapType{
            data: [
              {%Atom{value: :a}, %Integer{value: 1}},
              {
                %Atom{value: :b},
                %MapType{
                  data: [
                    {%Atom{value: :p}, %Variable{name: :x}},
                    {%Atom{value: :r}, %Integer{value: 4}}
                  ]
               }},
              {%Atom{value: :c}, %Integer{value: 3}},
              {%Atom{value: :d},
               %MapType{
                 data: [
                   {%Atom{value: :m},
                    %Integer{value: 0}},
                   {%Atom{value: :n},
                    %Variable{name: :y}}
                 ]
               }}
            ]
          },
          right: %MapType{
            data: [
              {%Atom{value: :a}, %Integer{value: 1}},
              {%Atom{value: :b},
               %MapType{
                 data: [
                   {%Atom{value: :p},
                    %Integer{value: 9}},
                   {%Atom{value: :r},
                    %Integer{value: 4}}
                 ]
               }},
              {%Atom{value: :c}, %Integer{value: 3}},
              {%Atom{value: :d},
               %MapType{
                 data: [
                   {%Atom{value: :m},
                    %Integer{value: 0}},
                   {%Atom{value: :n},
                    %Integer{value: 8}}
                 ]
               }}
            ]
          }
        }

      assert result == expected
    end
  end

  describe "other transform/1" do
    test "function" do
      code = """
        def test(a, b) do
          1
          2
        end
      """

      ast = Transpiler.parse!(code)
      result = Transpiler.transform(ast)

      expected = %Function{
        args: [
          %Variable{name: :a},
          %Variable{name: :b}
        ],
        body: [
          %Integer{value: 1},
          %Integer{value: 2}
        ],
        name: :test
      }

      assert result == expected
    end

    test "module" do
      code = """
        defmodule Prefix.Test do
          def test(a, b) do
            1
            2
          end

          def test(a, b, c) do
            1
            2
            3
          end
        end
      """

      ast = Transpiler.parse!(code)
      result = Transpiler.transform(ast)

      expected =
        %Module{
          body: [
            %Function{
              args: [
                %Variable{name: :a},
                %Variable{name: :b}
              ],
              body: [
                %Integer{value: 1},
                %Integer{value: 2}
              ],
              name: :test
            },
            %Function{
              args: [
                %Variable{name: :a},
                %Variable{name: :b},
                %Variable{name: :c}
              ],
              body: [
                %Integer{value: 1},
                %Integer{value: 2},
                %Integer{value: 3}
              ],
              name: :test
            }
          ],
          name: "Prefix.Test"
        }
    end

    test "variable" do
      ast = Transpiler.parse!("x")
      assert Transpiler.transform(ast) == %Variable{name: :x}
    end
  end

  describe "primitives generate/1" do
    test "integer" do
      result = Transpiler.generate(%Integer{value: 123})
      assert result == "123"
    end
  end

  describe "other generate/1" do
    test "module" do
      module =
        %Module{
          body: [
            %Function{
              args: [
                %Variable{name: :a},
                %Variable{name: :b}
              ],
              body: [
                %Integer{value: 1},
                %Integer{value: 2}
              ],
              name: :test_1
            },
            %Atom{value: :non_function},
            %Function{
              args: [
                %Variable{name: :a},
                %Variable{name: :b},
                %Variable{name: :c}
              ],
              body: [
                %Integer{value: 1},
                %Integer{value: 2},
                %Integer{value: 3}
              ],
              name: :test_1
            },
            %Atom{value: :non_function},
            %Function{
              args: [
                %Variable{name: :a},
                %Variable{name: :b}
              ],
              body: [
                %Integer{value: 1},
                %Integer{value: 2}
              ],
              name: :test_2
            },
          ],
          name: "Prefix.Test"
        }

      result = Transpiler.generate(module)

      expected = """
        class PrefixTest {
          static test_1() { }
          static test_2() { }
        }
        """

      assert result == expected
    end
  end

  # TODO: REFACTOR:

  # describe "aggregate_assignments/2" do

  #   test "map, root and nested keys" do
  #     result =
  #       Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: z, d: %{m: 0, n: y}}")
  #       |> Transpiler.transform()
  #       |> Transpiler.aggregate_assignments()

  #     assert result ==
  #       [
  #         [:x, [:map_access, :b], [:map_access, :p]],
  #         [:z, [:map_access, :c]],
  #         [:y, [:map_access, :d], [:map_access, :n]]
  #       ]
  #   end
  # end

  # describe "generate/1" do
  #   test "string" do
  #     result = Transpiler.generate({:string, "Test"})
  #     assert result == "'Test'"
  #   end

  #   test "map, not nested" do
  #     map = {:map, [a: {:integer, 1}, b: {:integer, 2}]}
  #     result = Transpiler.generate(map)

  #     assert result == "{ 'a': 1, 'b': 2 }"
  #   end

  #   test "map, nested" do
  #     map = {
  #       :map,
  #       [
  #         a: {:integer, 1},
  #         b: {
  #           :map,
  #           [
  #             c: {:integer, 2},
  #             d: {
  #               :map,
  #               [
  #                 e: {:integer, 3},
  #                 f: {:integer, 4}
  #               ]
  #             }
  #           ]
  #         }
  #       ]
  #     }

  #     result = Transpiler.generate(map)
  #     assert result == "{ 'a': 1, 'b': { 'c': 2, 'd': { 'e': 3, 'f': 4 } } }"
  #   end

  #   test "assignment, simple" do
  #     code = "x = 1"

  #     result =
  #       Transpiler.parse!(code)
  #       |> Transpiler.transform()
  #       |> Transpiler.generate()

  #     assert result == "x = 1;"
  #   end

  #   test "assignment, nested" do
  #     left = "%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}}"
  #     right = "%{a: 1, b: %{p: 9, r: 4}, c: 3, d: %{m: 0, n: 8}}"
  #     code = "#{left} = #{right}"

  #     result =
  #     Transpiler.parse!(code)
  #     |> Transpiler.transform()
  #     |> Transpiler.generate()

  #     expected = "x = { 'a': 1, 'b': { 'p': 9, 'r': 4 }, 'c': 3, 'd': { 'm': 0, 'n': 8 } }['b']['p'];\ny = { 'a': 1, 'b': { 'p': 9, 'r': 4 }, 'c': 3, 'd': { 'm': 0, 'n': 8 } }['d']['n'];"
  #     assert result == expected
  #   end
  # end

  # describe "transform/1" do
  #   test "destructure" do
  #     ast = Transpiler.parse!("head | tail")
  #     assert Transpiler.transform(ast) == {:destructure, {{:var, :head}, {:var, :tail}}}
  #   end

  #   test "if" do
  #     ast = Transpiler.parse!("if true, do: 1, else: 2")
  #     assert Transpiler.transform(ast) == {:if, {{:boolean, true}, {:integer, 1}, {:integer, 2}}}
  #   end

  #   test "case" do
  #     ast = Transpiler.parse!("case x do 1 -> :result_1; 2 -> :result_2 end")
  #     result = Transpiler.transform(ast)

  #     expected = {
  #       :case,
  #       {:var, :x},
  #       [
  #         {:clause, {:integer, 1}, {:atom, :result_1}},
  #         {:clause, {:integer, 2}, {:atom, :result_2}}
  #       ]
  #     }

  #     assert result == expected
  #   end
  # end
end
