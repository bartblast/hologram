defmodule Reflex.Transpiler do
  defmodule Atom do
    defstruct value: nil
  end

  defmodule Boolean do
    defstruct value: nil
  end

  defmodule Function do
    defstruct name: nil, args: nil, body: nil
  end

  defmodule Integer do
    defstruct value: nil
  end

  defmodule Map do
    defstruct data: nil
  end

  defmodule Matching do
    defstruct left: nil, right: nil
  end

  defmodule String do
    defstruct value: nil
  end

  defmodule Variable do
    defstruct name: nil
  end

  def parse!(str) do
    case Code.string_to_quoted(str) do
      {:ok, ast} ->
        ast

      _ ->
        raise "Invalid code"
    end
  end

  def parse_file(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted()
  end

  def transform(ast)

  # PRIMITIVES

  # boolean must be before atom
  def transform(ast) when is_boolean(ast) do
    %Boolean{value: ast}
  end

  def transform(ast) when is_atom(ast) do
    %Atom{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %Integer{value: ast}
  end

  def transform(ast) when is_binary(ast) do
    %String{value: ast}
  end

  # DATA STRUCTURES

  def transform({:%{}, _, map}) do
    data = Enum.map(map, fn {k, v} -> {transform(k), transform(v)} end)

    %Map{data: data}
  end

  # OPERATORS

  def transform({:=, _, [left, right]}) do
    left = transform(left) |> aggregate_assignments()
    %Matching{left: left, right: transform(right)}
  end

  def aggregate_assignments(_, path \\ [])

  def aggregate_assignments(%Variable{name: name} = var, path) do
    [[var] ++ path]
  end

  # OTHER

  def transform({:def, _, [{name, _, args}, [do: {_, _, body}]]}) do
    args = Enum.map(args, fn arg -> transform(arg) end)
    body = Enum.map(body, fn expr -> transform(expr) end)

    %Function{name: name, args: args, body: body}
  end

  def transform({name, _, nil}) when is_atom(name) do
    %Variable{name: name}
  end

  # TODO: REFACTOR:

  # def aggregate_assignments({:map, map}, path) do
  #   Enum.reduce(map, [], fn {k, v}, acc ->
  #     acc ++ aggregate_assignments(v, path ++ [[:map_access, k]])
  #   end)
  # end

  # def aggregate_assignments(_, path) do
  #   []
  # end

  # def generate({:assignment, left, right}) do
  #   Enum.map(left, fn pattern ->
  #     case pattern do
  #       [var | path] ->
  #         "#{var} = #{generate(right)}#{generate_assignment_path(path)};"
  #     end
  #   end)
  #   |> Enum.join("\n")
  # end

  # def generate_assignment_path([]) do
  #   ""
  # end

  # def generate_assignment_path([:map_access, key]) do
  #   "['#{key}']"
  # end

  # def generate_assignment_path(path) do
  #   Enum.map(path, fn access_spec ->
  #     generate_assignment_path(access_spec)
  #   end)
  #   |> Enum.join("")
  # end

  # def generate({:integer, value}) do
  #   "#{value}"
  # end

  # def generate({:string, value}) do
  #   "'#{value}'"
  # end

  # def generate({:map, value}) do
  #   fields =
  #     Enum.map(value, fn {k, v} -> "'#{k}': #{generate(v)}" end)
  #     |> Enum.join(", ")

  #   "{ #{fields} }"
  # end

  # def transform({:|, _, [var_1, var_2]}) do
  #   {:destructure, {transform(var_1), transform(var_2)}}
  # end

  # def transform({:if, _, [condition, [do: do_block, else: else_block]]}) do
  #   {:if, {transform(condition), transform(do_block), transform(else_block)}}
  # end

  # def transform({:case, _, [expression, [do: cases]]}) do
  #   {:case, transform(expression), Enum.map(cases, fn c -> transform(c) end)}
  # end

  # def transform({:->, _, [[clause], block]}) do
  #   {:clause, transform(clause), transform(block)}
  # end
end
