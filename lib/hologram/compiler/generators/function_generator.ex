# TODO: refactor & test

defmodule Hologram.Compiler.FunctionGenerator do
  alias Hologram.Compiler.AST.{MapAccess, Variable}
  alias Hologram.Compiler.Generator

  def generate(name, variants, context) do
    body =
      case generate_function_body(variants, context) do
        # TODO: determine what's this case for, comment and test it
        "" ->
          "{}\n"

        exprs ->
          "{\n#{exprs}}"
      end

    "static #{name}() #{body}\n"
  end

  defp generate_function_body(variants, context) do
    valid_cases =
      Enum.reduce(variants, "", fn variant, acc ->
        statement = if acc == "", do: "if", else: "else if"

        params = generate_function_params(variant, context)
        vars = generate_function_vars(variant)
        body = generate_function_expressions(variant, context)

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

  defp generate_function_expressions(variant, context) do
    expr_count = Enum.count(variant.body)

    Stream.with_index(variant.body)
    |> Enum.map(fn {expr, idx} ->
      return = if idx == expr_count - 1, do: "return ", else: ""
      "#{return}#{Generator.generate(expr, context)};"
    end)
    |> Enum.join("\n")
  end

  defp generate_function_params(variant, context) do
    params =
      Enum.map(variant.params, fn param -> Generator.generate(param, context, boxed: true) end)
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
