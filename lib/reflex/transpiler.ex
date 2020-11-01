defmodule Reflex.Transpiler do
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

  def transpile(ast)

  def transpile(ast) when is_binary(ast) do
    {:string, ast}
  end

  def transpile(ast) when is_integer(ast) do
    {:integer, ast}
  end

  def transpile(ast) when is_boolean(ast) do
    {:boolean, ast}
  end

  def transpile(ast) when is_atom(ast) do
    {:atom, ast}
  end

  def transpile({:%{}, _, map}) do
    {:map, Enum.map(map, fn {k, v} -> {k, transpile(v)} end)}
  end

  def transpile({:|, _, [var_1, var_2]}) do
    {:destructure, {transpile(var_1), transpile(var_2)}}
  end

  def transpile({var, _, nil}) when is_atom(var) do
    {:var, var}
  end

  def transpile({:if, _, [condition, [do: do_block, else: else_block]]}) do
    {:if, {transpile(condition), transpile(do_block), transpile(else_block)}}
  end
end
