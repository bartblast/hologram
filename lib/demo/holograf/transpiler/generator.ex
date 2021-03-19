defmodule Holograf.Transpiler.Generator do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{MapType, StructType}
  alias Holograf.Transpiler.AST.{Function, Module}

  # PRIMITIVES

  def generate(%AtomType{value: value}) do
    "'#{value}'"
  end

  def generate(%BooleanType{value: value}) do
    "#{value}"
  end

  def generate(%IntegerType{value: value}) do
    "#{value}"
  end

  def generate(%StringType{value: value}) do
    "'#{value}'"
  end

  # DATA STRUCTURES

  def generate(%MapType{data: data}) do
    fields = generate_object_fields(data)

    if fields != "" do
      "{ #{fields} }"
    else
      "{}"
    end
  end

  def generate_object_fields(ast) do
    Enum.map(ast, fn {k, v} -> "#{generate(k)}: #{generate(v)}" end)
    |> Enum.join(", ")
  end

  # OTHER

  def generate(%Module{name: name} = module) do
    functions =
      aggregate_functions(module)
      |> Enum.map(fn {k, v} ->
        body =
          case generate_function_body(v) do
            "" ->
              "{}"
            exprs ->
              "{ #{exprs} }"
          end

        "  static #{k}() #{body}"
      end)
      |> Enum.join("\n")

    """
    class #{generate_module_name(name)} {
    #{functions}
    }
    """
  end

  defp aggregate_functions(module) do
    Enum.reduce(module.functions, %{}, fn expr, acc ->
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

  # TODO: implement
  defp generate_function_body(variants) do
    ""
  end

  # HELPERS

  defp generate_module_name(ast) do
    String.replace("#{ast}", ".", "")
  end
end
