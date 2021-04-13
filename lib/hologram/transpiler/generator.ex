defmodule Hologram.Transpiler.Generator do
  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Transpiler.AST.{ListType, MapType, StructType}
  alias Hologram.Transpiler.AST.{MapAccess}
  alias Hologram.Transpiler.AST.{Call, Function, Module, Variable}

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
    data = generate_map_data(data)
    "{ type: 'map', data: #{data} }"
  end

  def generate(%StructType{module: module, data: data}) do
    module = generate_module_fully_qualified_name(module)
    data = generate_map_data(data)

    "{ type: 'struct', module: '#{module}', data: #{data} }"
  end

  def generate_map_data(ast) do
    fields =
      Enum.map(ast, fn {k, v} ->
        "'#{generate_object_key(k)}': #{generate(v)}"
      end)
      |> Enum.join(", ")

    if fields != "" do
      "{ #{fields} }"
    else
      "{}"
    end
  end

  defp generate_object_key(%AtomType{value: value}) do
    "~Hologram.Transpiler.AST.AtomType[#{value}]"
  end

  defp generate_object_key(%BooleanType{value: value}) do
    "~Hologram.Transpiler.AST.BooleanType[#{value}]"
  end

  defp generate_object_key(%IntegerType{value: value}) do
    "~Hologram.Transpiler.AST.IntegerType[#{value}]"
  end

  defp generate_object_key(%StringType{value: value}) do
    "~Hologram.Transpiler.AST.StringType[#{value}]"
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
      #{statement} (Hologram.patternMatchFunctionArgs(#{params}, arguments)) {
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
    "{ type: 'variable' }"
  end

  def generate(%Call{module: module, function: function, params: params}) do
    class = generate_class_name(module)

    params =
      Enum.map(params, fn param ->
        case param do
          %Variable{name: name} ->
            name
          _ ->
            generate(param)
        end
      end)
      |> Enum.join(", ")

    "#{class}.#{function}(#{params})"
  end

  # HELPERS

  def generate_class_name(module) do
    generate_module_fully_qualified_name(module)
    |> String.replace(".", "")
  end

  defp generate_module_fully_qualified_name(module) do
    Enum.join(module, ".")
  end
end
