defmodule Reflex.TranspilerTest do
  use ExUnit.Case

  alias Reflex.Transpiler
  alias Reflex.Transpiler.Atom
  alias Reflex.Transpiler.Boolean
  alias Reflex.Transpiler.Function
  alias Reflex.Transpiler.Integer
  alias Reflex.Transpiler.MapType
  alias Reflex.Transpiler.Module
  alias Reflex.Transpiler.StringType
  alias Reflex.Transpiler.Variable

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

  describe "parse!/1" do
    test "valid code" do
      assert Transpiler.parse!("1 + 2") == {:+, [line: 1], [1, 2]}
    end

    test "invalid code" do
      assert_raise RuntimeError, "Invalid code", fn ->
        Transpiler.parse!(".1")
      end
    end
  end

  describe "parse_file/1" do
    test "valid code" do
      assert {:ok, _} = Transpiler.parse_file("lib/demo/reflex/transpiler.ex")
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
  #   test "var" do
  #     result =
  #       Transpiler.parse!("x")
  #       |> Transpiler.transform()
  #       |> Transpiler.aggregate_assignments()

  #     assert result == [[:x]]
  #   end

  #   test "map, root keys" do
  #     result =
  #       Transpiler.parse!("%{a: x, b: y}")
  #       |> Transpiler.transform()
  #       |> Transpiler.aggregate_assignments()

  #     assert result == [
  #       [:x, [:map_access, :a]],
  #       [:y, [:map_access, :b]]
  #     ]
  #   end

  #   test "map, nested keys" do
  #     result =
  #       Transpiler.parse!("%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}}")
  #       |> Transpiler.transform()
  #       |> Transpiler.aggregate_assignments()

  #     assert result ==
  #       [
  #         [:x, [:map_access, :b], [:map_access, :p]],
  #         [:y, [:map_access, :d], [:map_access, :n]]
  #       ]
  #   end

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


  #   test "matching simple" do
  #     ast = Transpiler.parse!("x = 1")
  #     assert Transpiler.transform(ast) == {, [[:x]], {:integer, 1}}
  #   end

  #   test "assignment complex" do
  #     result =
  #       Transpiler.parse!("%{a: x, b: y} = %{a: 1, b: 2}")
  #       |> Transpiler.transform()

  #     assert result == {
  #       :assignment,
  #       [
  #         [:x, [:map_access, :a]],
  #         [:y, [:map_access, :b]]
  #       ],
  #       {:map, [a: {:integer, 1}, b: {:integer, 2}]},
  #     }
  #   end

  #   test "destructure" do
  #     ast = Transpiler.parse!("head | tail")
  #     assert Transpiler.transform(ast) == {:destructure, {{:var, :head}, {:var, :tail}}}
  #   end

  #   test "map with var match" do
  #     ast = Transpiler.parse!("%{a: 1, b: x}")
  #     assert Transpiler.transform(ast) == {:map, [a: {:integer, 1}, b: {:var, :x}]}
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
