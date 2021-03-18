# # TODO: refactor
# defmodule Holograf.Transpiler do

#   # TODO: REFACTOR:

#   # def generate({:assignment, left, right}) do
#   #   Enum.map(left, fn pattern ->
#   #     case pattern do
#   #       [var | path] ->
#   #         "#{var} = #{generate(right)}#{generate_assignment_path(path)};"
#   #     end
#   #   end)
#   #   |> Enum.join("\n")
#   # end

#   # def generate_assignment_path([]) do
#   #   ""
#   # end

#   # def generate_assignment_path([:map_access, key]) do
#   #   "['#{key}']"
#   # end

#   # def generate_assignment_path(path) do
#   #   Enum.map(path, fn access_spec ->
#   #     generate_assignment_path(access_spec)
#   #   end)
#   #   |> Enum.join("")
#   # end
# end
