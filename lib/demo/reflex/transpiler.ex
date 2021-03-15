defmodule Reflex.Transpiler do
  def aggregate_assignments(_, path \\ [])

  def aggregate_assignments({:var, var}, path) do
    [[var] ++ path]
  end

  def aggregate_assignments({:map, map}, path) do
    Enum.reduce(map, [], fn {k, v}, acc ->
      acc ++ aggregate_assignments(v, path ++ [[:map_access, k]])
    end)
  end

  def aggregate_assignments(_, path) do
    []
  end

  def generate({:assignment, left, right}) do
    Enum.map(left, fn pattern ->
      case pattern do
        [var | path] ->
          "#{var} = #{generate(right)}#{generate_assignment_path(path)};"
      end
    end)
    |> Enum.join("\n")
  end

  def generate_assignment_path([]) do
    ""
  end

  def generate_assignment_path([:map_access, key]) do
    "['#{key}']"
  end

  def generate_assignment_path(path) do
    Enum.map(path, fn access_spec ->
      generate_assignment_path(access_spec)
    end)
    |> Enum.join("")
  end

  def generate({:integer, value}) do
    "#{value}"
  end

  def generate({:string, value}) do
    "'#{value}'"
  end

  def generate({:map, value}) do
    fields =
      Enum.map(value, fn {k, v} -> "'#{k}': #{generate(v)}" end)
      |> Enum.join(", ")

    "{ #{fields} }"
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

  def transform(ast) when is_binary(ast) do
    {:string, ast}
  end

  def transform(ast) when is_integer(ast) do
    {:integer, ast}
  end

  def transform(ast) when is_boolean(ast) do
    {:boolean, ast}
  end

  def transform(ast) when is_atom(ast) do
    {:atom, ast}
  end

  def transform({:%{}, _, map}) do
    {:map, Enum.map(map, fn {k, v} -> {k, transform(v)} end)}
  end

  def transform({:=, _, [left, right]}) do
    left = transform(left) |> aggregate_assignments()
    {:assignment, left, transform(right)}
  end

  def transform({var, _, nil}) when is_atom(var) do
    {:var, var}
  end

  def transform({:|, _, [var_1, var_2]}) do
    {:destructure, {transform(var_1), transform(var_2)}}
  end

  def transform({:if, _, [condition, [do: do_block, else: else_block]]}) do
    {:if, {transform(condition), transform(do_block), transform(else_block)}}
  end

  def transform({:case, _, [expression, [do: cases]]}) do
    {:case, transform(expression), Enum.map(cases, fn c -> transform(c) end)}
  end

  def transform({:->, _, [[clause], block]}) do
    {:clause, transform(clause), transform(block)}
  end
end
