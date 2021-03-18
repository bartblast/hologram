defmodule Holograf.Transpiler.Transformer do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.MapType
  alias Holograf.Transpiler.AST.MatchOperator
  alias Holograf.Transpiler.AST.MapAccess
  alias Holograf.Transpiler.AST.{Function, Variable}

  def transform(ast)

  # PRIMITIVES

  # boolean must be before atom
  def transform(ast) when is_boolean(ast) do
    %BooleanType{value: ast}
  end

  def transform(ast) when is_atom(ast) do
    %AtomType{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %IntegerType{value: ast}
  end

  def transform(ast) when is_binary(ast) do
    %StringType{value: ast}
  end

  # DATA STRUCTURES

  def transform({:%{}, _, map}) do
    data = Enum.map(map, fn {k, v} -> {transform(k), transform(v)} end)
    %MapType{data: data}
  end

  # OPERATORS

  def transform({:=, _, [left, right]}) do
    left = transform(left)

    %MatchOperator{
      bindings: bindings(left),
      left: left,
      right: transform(right)
    }
  end

  defp bindings(_, path \\ [])

  defp bindings(%Variable{name: name} = var, path) do
    [[var] ++ path]
  end

  defp bindings(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {k, v}, acc ->
      acc ++ bindings(v, path ++ [%MapAccess{key: k}])
    end)
  end

  defp bindings(_, path) do
    []
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
end
