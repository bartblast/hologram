# # TODO: refactor
# defmodule Holograf.TranspilerTest do
#   use ExUnit.Case

#   describe "other generate/1" do
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
# end
