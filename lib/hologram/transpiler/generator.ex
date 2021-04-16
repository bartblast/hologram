defmodule Hologram.Transpiler.Generator do
  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, ListType, MapType, StringType, StructType}
  alias Hologram.Transpiler.AST.{Call, Function, MapAccess, Module, Variable}
  alias Hologram.Transpiler.Generators.{MapTypeGenerator, PrimitiveTypeGenerator, StructTypeGenerator}
  alias Hologram.Transpiler.Helpers

  # TYPES

  def generate(%AtomType{value: value}) do
    PrimitiveTypeGenerator.generate(:atom, "'#{value}'")
  end

  def generate(%BooleanType{value: value}) do
    PrimitiveTypeGenerator.generate(:boolean, "#{value}")
  end

  def generate(%IntegerType{value: value}) do
    PrimitiveTypeGenerator.generate(:integer, "#{value}")
  end

  def generate(%MapType{data: data}) do
    MapTypeGenerator.generate(data)
  end

  def generate(%StructType{module: module, data: data}) do
    StructTypeGenerator.generate(module, data)
  end

  def generate(%StringType{value: value}) do
    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
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
    valid_cases =
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

    invalid_case = """
    else {
      throw 'No match for the function call'
    }
    """

    valid_cases <> invalid_case
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

  defp generate_class_name(module) do
    Helpers.module_name(module)
    |> String.replace(".", "")
  end
end
