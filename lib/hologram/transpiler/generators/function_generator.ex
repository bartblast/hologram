# TODO: refactor & test

defmodule Hologram.Transpiler.FunctionGenerator do
  alias Hologram.Transpiler.AST.{MapAccess, Variable}
  alias Hologram.Transpiler.Generator

  def generate(name, variants) do
    body =
      case generate_function_body(variants) do
        # TODO: determine what's this case for, comment and test it
        "" ->
          "{}\n"

        exprs ->
          "{\n#{exprs}}"
      end

    "static #{name}() #{body}\n"
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
      "#{return}#{Generator.generate(expr)};"
    end)
    |> Enum.join("\n")
  end

  defp generate_function_params(variant) do
    params =
      Enum.map(variant.params, fn param -> Generator.generate(param) end)
      |> Enum.join(", ")

    "[ #{params} ]"
  end

  defp generate_function_vars(variant) do
    Enum.map(variant.bindings, fn {name, {idx, binding}} ->
      acc = "let #{List.last(binding).name} = "

      Enum.reduce(binding, acc, fn access, acc ->
        acc
        <>
        case access do
          %Variable{name: name} ->
            "arguments[#{idx}]"

          %MapAccess{key: key} ->
            "['#{key}']"
        end
      end)
      <>
      ";"
    end)
    |> Enum.join("\n")
  end
end
