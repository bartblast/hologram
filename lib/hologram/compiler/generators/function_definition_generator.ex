defmodule Hologram.Compiler.FunctionDefinitionGenerator do
  alias Hologram.Compiler.IR.{AccessOperator, Variable}
  alias Hologram.Compiler.{Generator, MapKeyGenerator}

  def generate(name, variants, context) do
    body = generate_body(variants, context)
    "static #{name}() {\n#{body}}\n"
  end

  defp generate_body(variants, context) do
    generate_body_valid_cases(variants, context) <> generate_body_invalid_case()
  end

  defp generate_body_invalid_case do
    """
    else {
    throw 'No match for the function call'
    }
    """
  end

  defp generate_body_valid_cases(variants, context) do
    Enum.reduce(variants, "", fn variant, acc ->
      statement = if acc == "", do: "if", else: "else if"
      params = generate_params(variant, context)
      vars = generate_vars(variant)
      body = generate_exprs(variant, context)

      code = """
      #{statement} (Hologram.patternMatchFunctionArgs(#{params}, arguments)) {#{vars}#{body}
      }
      """

      acc <> code
    end)
  end

  defp generate_expr(expr, idx, expr_count, context) do
    return = if idx == expr_count - 1, do: "return ", else: ""
    "\n#{return}#{Generator.generate(expr, context)};"
  end

  defp generate_exprs(variant, context) do
    expr_count = Enum.count(variant.body)

    Enum.with_index(variant.body)
    |> Enum.map(fn {expr, idx} -> generate_expr(expr, idx, expr_count, context) end)
  end

  defp generate_params(variant, context) do
    params =
      Enum.map(variant.params, &Generator.generate(&1, context, boxed: true))
      |> Enum.join(", ")

    "[#{params}]"
  end

  defp generate_var({name, {idx, path}}) do
    acc = "\nlet #{name} = arguments[#{idx}]"

    value =
      Enum.reduce(path, acc, fn type, acc ->
        acc
        <>
        case type do
          %AccessOperator{key: key} ->
            ".data['#{MapKeyGenerator.generate(key)}']"

          %Variable{name: name} ->
            ""
        end
      end)

    "#{value};"
  end

  defp generate_vars(variant) do
    Enum.map(variant.bindings, &generate_var(&1))
  end
end
