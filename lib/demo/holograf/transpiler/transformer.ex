defmodule Holograf.Transpiler.Transformer do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{ListType, MapType, StructType}
  alias Holograf.Transpiler.AST.MatchOperator
  alias Holograf.Transpiler.AST.MapAccess
  alias Holograf.Transpiler.AST.{Alias, Function, Module, Variable}

  def transform(ast, aliases \\ %{})

  # PRIMITIVES

  # boolean must be before atom
  def transform(ast, _aliases) when is_boolean(ast) do
    %BooleanType{value: ast}
  end

  def transform(ast, _aliases) when is_atom(ast) do
    %AtomType{value: ast}
  end

  def transform(ast, _aliases) when is_integer(ast) do
    %IntegerType{value: ast}
  end

  def transform(ast, _aliases) when is_binary(ast) do
    %StringType{value: ast}
  end

  # DATA STRUCTURES

  def transform(ast, aliases) when is_list(ast) do
    data = Enum.map(ast, fn v -> transform(v, aliases) end)
    %ListType{data: data}
  end

  def transform({:%{}, _, ast}, aliases) do
    data = Enum.map(ast, fn {k, v} ->
      {transform(k, aliases), transform(v, aliases)}
    end)

    %MapType{data: data}
  end

  def transform({:%, _, [{_, _, module}, ast]}, aliases) do
    data = transform(ast, aliases).data

    key = List.last(module)

    module =
      if Map.has_key?(aliases, key) do
        aliases[key]
      else
        module
      end

    %StructType{module: module, data: data}
  end

  # OPERATORS

  def transform({:=, _, [left, right]}, aliases) do
    left = transform(left, aliases)

    %MatchOperator{
      bindings: bindings(left),
      left: left,
      right: transform(right, aliases)
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

  def transform({:alias, _, [{:__aliases__, _, module}]}, _aliases) do
    %Alias{module: module}
  end

  def transform({:def, _, [{name, _, args}, [do: body]]}, aliases) do
    args = Enum.map(args, fn arg -> transform(arg, aliases) end)

    body =
      case body do
        {:__block__, _, block} ->
          block
        expr ->
          [expr]
      end
      |> Enum.map(fn expr -> transform(expr, aliases) end)

    %Function{name: name, args: args, body: body}
  end

  def transform({:defmodule, _, [{_, _, name}, [do: {_, _, ast}]]}, _aliases) do
    name =
      Enum.map(name, fn part -> "#{part}" end)
      |> Enum.join(".")

    aliases = aggregate_aliases(ast)
    functions = aggregate_functions(ast, aliases.map)

    %Module{name: name, aliases: aliases, functions: functions}
  end

  defp aggregate_aliases(ast) do
    list =
      Enum.reduce(ast, [], fn expr, acc ->
        case expr do
          {:alias, _, _} ->
            acc ++ [transform(expr)]
          _ ->
            acc
        end
      end)

    map =
      Enum.reduce(list, %{}, fn elem, acc ->
        Map.put(acc, List.last(elem.module), elem.module)
      end)

    %{list: list, map: map}
  end

  defp aggregate_functions(ast, aliases) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {:def, _, _} ->
          acc ++ [transform(expr, aliases)]
        _ ->
          acc
      end
    end)
  end

  def transform({name, _, nil}, _aliases) when is_atom(name) do
    %Variable{name: name}
  end
end
