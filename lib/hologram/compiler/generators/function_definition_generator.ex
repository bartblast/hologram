defmodule Hologram.Compiler.FunctionDefinitionGenerator do
  alias Hologram.Compiler.{Context, Formatter, Generator, MapKeyGenerator, Opts}
  alias Hologram.Compiler.IR.{AccessOperator, Variable}

  def generate(name, variants, %Context{} = context, %Opts{} = opts) do
    body = generate_body(variants, context, opts)

    "static #{name}() {#{body}"
    |> Formatter.maybe_append_new_line("}")
    |> Formatter.append_line_break()
  end

  defp generate_body(variants, context, opts) do
    invalid_case = generate_body_invalid_case()

    generate_body_valid_cases(variants, context, opts)
    |> Formatter.maybe_append_new_line(invalid_case)
  end

  defp generate_body_invalid_case do
    """
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }\
    """
  end

  defp generate_body_valid_cases(variants, context, opts) do
    Enum.reduce(variants, "", fn variant, acc ->
      statement = if acc == "", do: "if", else: "else if"
      params = generate_params(variant, context)
      vars = generate_vars(variant, context)
      body = generate_exprs(variant, context, opts)

      acc
      |> Formatter.maybe_append_new_line("#{statement} (Hologram.patternMatchFunctionArgs(#{params}, arguments)) {")
      |> Formatter.maybe_append_new_line(vars)
      |> Formatter.maybe_append_new_line(body)
      |> Formatter.maybe_append_new_line("}")
    end)
  end

  defp generate_expr(expr, idx, expr_count, context, opts) do
    return = if idx == expr_count - 1, do: "return ", else: ""
    "#{return}#{Generator.generate(expr, context, opts)};"
  end

  defp generate_exprs(variant, context, opts) do
    expr_count = Enum.count(variant.body)

    Enum.with_index(variant.body)
    |> Enum.map(fn {expr, idx} -> generate_expr(expr, idx, expr_count, context, opts) end)
    |> Enum.join("\n")
  end

  defp generate_params(variant, context) do
    params =
      Enum.map(variant.params, &Generator.generate(&1, context, %Opts{placeholder: true}))
      |> Enum.join(", ")

    "[#{params}]"
  end

  defp generate_var({name, {idx, path}}, context) do
    acc = "let #{name} = arguments[#{idx}]"

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
    |> Enum.join("\n")
  end
end
