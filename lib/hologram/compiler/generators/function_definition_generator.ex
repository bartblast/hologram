defmodule Hologram.Compiler.FunctionDefinitionGenerator do
  alias Hologram.Compiler.{Context, Generator, MapKeyGenerator, Opts}
  alias Hologram.Compiler.IR.{AccessOperator, Variable}

  def generate(name, variants, %Context{} = context, %Opts{} = opts) do
    body = generate_body(variants, context, opts)
    "static #{name}() {\n#{body}}\n"
  end

  defp generate_body(variants, context, opts) do
    generate_body_valid_cases(variants, context, opts) <> generate_body_invalid_case()
  end

  defp generate_body_invalid_case do
    """
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    """
  end

  defp generate_body_valid_cases(variants, context, opts) do
    Enum.reduce(variants, "", fn variant, acc ->
      statement = if acc == "", do: "if", else: "else if"
      params = generate_params(variant, context)
      vars = generate_vars(variant, context)
      body = generate_exprs(variant, context, opts)

      code = """
      #{statement} (Hologram.patternMatchFunctionArgs(#{params}, arguments)) {#{vars}#{body}
      }
      """

      acc <> code
    end)
  end

  defp generate_expr(expr, idx, expr_count, context, opts) do
    return = if idx == expr_count - 1, do: "return ", else: ""
    "\n#{return}#{Generator.generate(expr, context, opts)};"
  end

  defp generate_exprs(variant, context, opts) do
    expr_count = Enum.count(variant.body)

    Enum.with_index(variant.body)
    |> Enum.map(fn {expr, idx} -> generate_expr(expr, idx, expr_count, context, opts) end)
  end

  defp generate_params(variant, context) do
    params =
      Enum.map(variant.params, &Generator.generate(&1, context, %Opts{placeholder: true}))
      |> Enum.join(", ")

    "[#{params}]"
  end

  defp generate_var({name, {idx, path}}, context) do
    acc = "\nlet #{name} = arguments[#{idx}]"

    value =
      Enum.reduce(path, acc, fn type, acc ->
        acc <>
          case type do
            %AccessOperator{key: key} ->
              ".data['#{MapKeyGenerator.generate(key, context)}']"

            %Variable{} ->
              ""
          end
      end)

    "#{value};"
  end

  defp generate_vars(variant, context) do
    Enum.map(variant.bindings, &generate_var(&1, context))
  end
end
