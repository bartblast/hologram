defmodule Holograf.Transpiler.Transformer do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{ListType, MapType}
  alias Holograf.Transpiler.AST.MatchOperator
  alias Holograf.Transpiler.AST.MapAccess
  alias Holograf.Transpiler.AST.{Alias, Function, Module, Variable}

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

  def transform(ast) when is_list(ast) do
    data = Enum.map(ast, fn v -> transform(v) end)
    %ListType{data: data}
  end

  def transform({:%{}, _, ast}) do
    data = Enum.map(ast, fn {k, v} -> {transform(k), transform(v)} end)
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

  def transform({:alias, _, [{:__aliases__, _, module}]}) do
    %Alias{module: module}
  end

  def transform({:def, _, [{name, _, args}, [do: body]]}) do
    args = Enum.map(args, fn arg -> transform(arg) end)

    body =
      case body do
        {:__block__, _, block} ->
          block
        expr ->
          [expr]
      end
      |> Enum.map(fn expr -> transform(expr) end)

    %Function{name: name, args: args, body: body}
  end

  def transform({:defmodule, _, [{_, _, name}, [do: {_, _, body}]]}) do
    name =
      Enum.map(name, fn part -> "#{part}" end)
      |> Enum.join(".")

    body = Enum.map(body, fn expr -> transform(expr) end)

    %Module{name: name, body: body}
  end

  def transform({name, _, nil}) when is_atom(name) do
    %Variable{name: name}
  end
end
