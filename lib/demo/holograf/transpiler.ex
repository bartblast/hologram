# # TODO: refactor
# defmodule Holograf.Transpiler do
#   defmodule Module do
#     defstruct name: nil, body: nil
#   end

#   def parse_file(path) do
#     path
#     |> File.read!()
#     |> Code.string_to_quoted()
#   end

#   # TRANSFORM

#   # OTHER

#   def transform({:defmodule, _, [{_, _, name}, [do: {_, _, body}]]}) do
#     name =
#       Enum.map(name, fn part -> "#{part}" end)
#       |> Enum.join(".")

#     body = Enum.map(body, fn expr -> transform(expr) end)
#     %Module{name: name, body: body}
#   end

#   def aggregate_functions(module) do
#     Enum.reduce(module.body, %{}, fn expr, acc ->
#       case expr do
#         %Function{name: name} = fun ->
#           if Map.has_key?(acc, name) do
#             Map.put(acc, name, acc[name] ++ [fun])
#           else
#             Map.put(acc, name, [fun])
#           end
#         _ ->
#           acc
#       end
#     end)
#   end

#   # GENERATE

#   # OTHER

#   def generate(%Module{name: name} = module) do
#     name = String.replace("#{name}", ".", "")

#     functions =
#       aggregate_functions(module)
#       |> Enum.map(fn {k, v} -> "  static #{k}() { #{generate_function_body(v)} }" end)
#       |> Enum.join("\n")

#     """
#     class #{name} {
#     #{functions}
#     }
#     """
#   end

#   def generate_function_body(function_variants) do
#   end

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

#   # def transform({:|, _, [var_1, var_2]}) do
#   #   {:destructure, {transform(var_1), transform(var_2)}}
#   # end

#   # def transform({:if, _, [condition, [do: do_block, else: else_block]]}) do
#   #   {:if, {transform(condition), transform(do_block), transform(else_block)}}
#   # end

#   # def transform({:case, _, [expression, [do: cases]]}) do
#   #   {:case, transform(expression), Enum.map(cases, fn c -> transform(c) end)}
#   # end

#   # def transform({:->, _, [[clause], block]}) do
#   #   {:clause, transform(clause), transform(block)}
#   # end
# end
