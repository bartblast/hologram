defmodule Holograf.Transpiler.Generator do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.{ListType, MapType, StructType}
  alias Holograf.Transpiler.AST.{MapAccess}
  alias Holograf.Transpiler.AST.{Function, Module, Variable}

  # PRIMITIVE TYPES

  def generate(%AtomType{value: value}) do
    generate_primitive_type(:atom, "'#{value}'")
  end

  def generate(%BooleanType{value: value}) do
    generate_primitive_type(:boolean, "#{value}")
  end

  def generate(%IntegerType{value: value}) do
    generate_primitive_type(:integer, "#{value}")
  end

  def generate(%StringType{value: value}) do
    generate_primitive_type(:string, "'#{value}'")
  end

  defp generate_primitive_type(type, value) do
    "{ type: '#{type}', value: #{value} }"
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

  def generate(%StructType{module: module, data: data}) do
    meta = "__type__: 'struct', __module__: '#{Enum.join(module, ".")}'"
    fields = generate_object_fields(data)

    if fields != "" do
      "{ #{meta}, #{fields} }"
    else
      "{ #{meta} }"
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
              "{}\n"
            exprs ->
              "{\n#{exprs}}"
          end

        "static #{k}() #{body}\n"
      end)
      |> Enum.join("\n")

    """
    class #{generate_class_name(name)} {

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

  defp generate_function_body(variants) do
    Enum.reduce(variants, "", fn variant, acc ->
      statement = if acc == "", do: "if", else: "else if"

      params = generate_function_params(variant)
      vars = generate_function_vars(variant)
      body = generate_function_expressions(variant)

      code = """
      #{statement} (patternMatchFunctionArgs(#{params}, arguments)) {
      #{vars}
      #{body}
      }
      """

      acc <> code
    end)
  end

  defp generate_function_expressions(variant) do
    expr_count = Enum.count(variant.body)

    Stream.with_index(variant.body)
    |> Enum.map(fn {expr, idx} ->
      return = if idx == expr_count - 1, do: "return ", else: ""
      "#{return}#{generate(expr)};"
    end)
    |> Enum.join("\n")
  end

  defp generate_function_params(variant) do
    params =
      Enum.map(variant.params, fn param -> generate(param) end)
      |> Enum.join(", ")

    "[ #{params} ]"
  end

  defp generate_function_vars(variant) do
    Stream.with_index(variant.bindings)
    |> Enum.map(fn {binding, idx} ->
      Enum.reduce(binding, "", fn access, accumulator ->
        part =
          case access do
            %Variable{name: name} ->
              "let #{name} = arguments[#{idx}]"
            %MapAccess{key: key} ->
              "['#{key}']"
          end

        accumulator <> part
      end)
      <> ";"
    end)
    |> Enum.join("\n")
  end

  def generate(%Variable{}) do
    "{ __type__: 'variable', __module__: 'Holograf.Transpiler.AST.Variable' }"
  end

  # HELPERS

  defp generate_class_name(ast) do
    String.replace("#{ast}", ".", "")
  end
end
