defmodule Reflex.Transpiler do
  def aggregate_assignments(_, path \\ [])

  def aggregate_assignments({:var, var}, path) do
    [path ++ [[var, :assign]]]
  end

  def aggregate_assignments({:map, map}, path) do
    Enum.reduce(map, [], fn {k, v}, acc ->
      acc ++ aggregate_assignments(v, path ++ [[:map_access, k]])
    end)
  end

  def aggregate_assignments(_, path) do
    []
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

  def transform({:|, _, [var_1, var_2]}) do
    {:destructure, {transform(var_1), transform(var_2)}}
  end

  def transform({var, _, nil}) when is_atom(var) do
    {:var, var}
  end

  def transform({:if, _, [condition, [do: do_block, else: else_block]]}) do
    {:if, {transform(condition), transform(do_block), transform(else_block)}}
  end
end
