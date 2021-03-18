# TODO: REFACTOR
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

  defmodule MapAccess do
    defstruct key: nil
  end

  defmodule MapType do
    defstruct data: nil
  end

  defmodule MatchOperator do
    defstruct bindings: nil, left: nil, right: nil
  end

  defmodule Module do
    defstruct name: nil, body: nil
  end

  defmodule StringType do
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

  # TRANSFORM

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

  def transform({:defmodule, _, [{_, _, name}, [do: {_, _, body}]]}) do
    name =
      Enum.map(name, fn part -> "#{part}" end)
      |> Enum.join(".")

    body = Enum.map(body, fn expr -> transform(expr) end)
    %Module{name: name, body: body}
  end

  def aggregate_functions(module) do
    Enum.reduce(module.body, %{}, fn expr, acc ->
      case expr do
        %Function{name: name} = fun ->
          if Map.has_key?(acc, name) do
            Map.put(acc, name, acc[name] ++ [fun])
          else
            Map.put(acc, name, [fun])
          end
        _ ->
          acc
      end
    end)
  end

  def transform({name, _, nil}) when is_atom(name) do
    %Variable{name: name}
  end

  # GENERATE

  # PRIMITIVES

  def generate(%Integer{value: value}) do
  "#{value}"
  end

  # OTHER

  def generate(%Module{name: name} = module) do
    name = String.replace("#{name}", ".", "")

    functions =
      aggregate_functions(module)
      |> Enum.map(fn {k, v} -> "  static #{k}() { #{generate_function_body(v)} }" end)
      |> Enum.join("\n")

    """
    class #{name} {
    #{functions}
    }
    """
  end

  def generate_function_body(function_variants) do
  end

  # TODO: REFACTOR:

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
