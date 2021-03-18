# # TODO: refactor
# defmodule Holograf.TranspilerTest do
#   use ExUnit.Case

#   test "aggregate_functions/1" do
#     module =
#       %Module{
#         body: [
#           %Function{
#             args: [
#               %Variable{name: :a},
#               %Variable{name: :b}
#             ],
#             body: [
#               %IntegerType{value: 1},
#               %IntegerType{value: 2}
#             ],
#             name: :test_1
#           },
#           %AtomType{value: :non_function},
#           %Function{
#             args: [
#               %Variable{name: :a},
#               %Variable{name: :b},
#               %Variable{name: :c}
#             ],
#             body: [
#               %IntegerType{value: 1},
#               %IntegerType{value: 2},
#               %IntegerType{value: 3}
#             ],
#             name: :test_1
#           },
#           %AtomType{value: :non_function},
#           %Function{
#             args: [
#               %Variable{name: :a},
#               %Variable{name: :b}
#             ],
#             body: [
#               %IntegerType{value: 1},
#               %IntegerType{value: 2}
#             ],
#             name: :test_2
#           },
#         ],
#         name: "Prefix.Test"
#       }

#     result = Transpiler.aggregate_functions(module)

#     expected = %{
#       test_1: [
#         %Function{
#           args: [
#             %Variable{name: :a},
#             %Variable{name: :b}
#           ],
#           body: [
#             %IntegerType{value: 1},
#             %IntegerType{value: 2}
#           ],
#           name: :test_1
#         },
#         %Function{
#           args: [
#             %Variable{name: :a},
#             %Variable{name: :b},
#             %Variable{name: :c}
#           ],
#           body: [
#             %IntegerType{value: 1},
#             %IntegerType{value: 2},
#             %IntegerType{value: 3}
#           ],
#           name: :test_1
#         }
#       ],
#       test_2: [
#         %Function{
#           args: [
#             %Variable{name: :a},
#             %Variable{name: :b}
#           ],
#           body: [
#             %IntegerType{value: 1},
#             %IntegerType{value: 2}
#           ],
#           name: :test_2
#         }
#       ]
#     }

#     assert result == expected
#   end

#   describe "parse_file/1" do
#     test "valid code" do
#       assert {:ok, _} = Transpiler.parse_file("lib/demo/holograf/transpiler.ex")
#     end

#     test "invalid code" do
#       assert {:error, _} = Transpiler.parse_file("README.md")
#     end
#   end

#   describe "other transform/1" do
#     test "function" do
#       code = """
#         def test(a, b) do
#           1
#           2
#         end
#       """

#       ast = Transpiler.parse!(code)
#       result = Transpiler.transform(ast)

#       expected = %Function{
#         args: [
#           %Variable{name: :a},
#           %Variable{name: :b}
#         ],
#         body: [
#           %IntegerType{value: 1},
#           %IntegerType{value: 2}
#         ],
#         name: :test
#       }

#       assert result == expected
#     end

#     test "module" do
#       code = """
#         defmodule Prefix.Test do
#           def test(a, b) do
#             1
#             2
#           end

#           def test(a, b, c) do
#             1
#             2
#             3
#           end
#         end
#       """

#       ast = Transpiler.parse!(code)
#       result = Transpiler.transform(ast)

#       expected =
#         %Module{
#           body: [
#             %Function{
#               args: [
#                 %Variable{name: :a},
#                 %Variable{name: :b}
#               ],
#               body: [
#                 %IntegerType{value: 1},
#                 %IntegerType{value: 2}
#               ],
#               name: :test
#             },
#             %Function{
#               args: [
#                 %Variable{name: :a},
#                 %Variable{name: :b},
#                 %Variable{name: :c}
#               ],
#               body: [
#                 %IntegerType{value: 1},
#                 %IntegerType{value: 2},
#                 %IntegerType{value: 3}
#               ],
#               name: :test
#             }
#           ],
#           name: "Prefix.Test"
#         }
#     end
#   end

#   describe "other generate/1" do
#     test "module" do
#       module =
#         %Module{
#           body: [
#             %Function{
#               args: [
#                 %Variable{name: :a},
#                 %Variable{name: :b}
#               ],
#               body: [
#                 %IntegerType{value: 1},
#                 %IntegerType{value: 2}
#               ],
#               name: :test_1
#             },
#             %AtomType{value: :non_function},
#             %Function{
#               args: [
#                 %Variable{name: :a},
#                 %Variable{name: :b},
#                 %Variable{name: :c}
#               ],
#               body: [
#                 %IntegerType{value: 1},
#                 %IntegerType{value: 2},
#                 %IntegerType{value: 3}
#               ],
#               name: :test_1
#             },
#             %AtomType{value: :non_function},
#             %Function{
#               args: [
#                 %Variable{name: :a},
#                 %Variable{name: :b}
#               ],
#               body: [
#                 %IntegerType{value: 1},
#                 %IntegerType{value: 2}
#               ],
#               name: :test_2
#             },
#           ],
#           name: "Prefix.Test"
#         }

#       result = Transpiler.generate(module)

#       expected = """
#         class PrefixTest {
#           static test_1() { }
#           static test_2() { }
#         }
#         """

#       assert result == expected
#     end
#   end

#   # describe "generate/1" do
#   #   test "assignment, simple" do
#   #     code = "x = 1"

#   #     result =
#   #       Transpiler.parse!(code)
#   #       |> Transpiler.transform()
#   #       |> Transpiler.generate()

#   #     assert result == "x = 1;"
#   #   end

#   #   test "assignment, nested" do
#   #     left = "%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}}"
#   #     right = "%{a: 1, b: %{p: 9, r: 4}, c: 3, d: %{m: 0, n: 8}}"
#   #     code = "#{left} = #{right}"

#   #     result =
#   #     Transpiler.parse!(code)
#   #     |> Transpiler.transform()
#   #     |> Transpiler.generate()

#   #     expected = "x = { 'a': 1, 'b': { 'p': 9, 'r': 4 }, 'c': 3, 'd': { 'm': 0, 'n': 8 } }['b']['p'];\ny = { 'a': 1, 'b': { 'p': 9, 'r': 4 }, 'c': 3, 'd': { 'm': 0, 'n': 8 } }['d']['n'];"
#   #     assert result == expected
#   #   end
#   # end

#   # describe "transform/1" do
#   #   test "destructure" do
#   #     ast = Transpiler.parse!("head | tail")
#   #     assert Transpiler.transform(ast) == {:destructure, {{:var, :head}, {:var, :tail}}}
#   #   end

#   #   test "if" do
#   #     ast = Transpiler.parse!("if true, do: 1, else: 2")
#   #     assert Transpiler.transform(ast) == {:if, {{:boolean, true}, {:integer, 1}, {:integer, 2}}}
#   #   end

#   #   test "case" do
#   #     ast = Transpiler.parse!("case x do 1 -> :result_1; 2 -> :result_2 end")
#   #     result = Transpiler.transform(ast)

#   #     expected = {
#   #       :case,
#   #       {:var, :x},
#   #       [
#   #         {:clause, {:integer, 1}, {:atom, :result_1}},
#   #         {:clause, {:integer, 2}, {:atom, :result_2}}
#   #       ]
#   #     }

#   #     assert result == expected
#   #   end
#   # end
# end
