defmodule Hologram.Compiler.FunctionDefinitionGenerator do
  import Hologram.Commons.Encoder
  import Hologram.Compiler.Encoder.Commons

  alias Hologram.Compiler.{Context, Formatter, Generator, Opts}

  def generate(name, variants, %Context{} = context, %Opts{} = opts) do
    body = generate_body(variants, context, opts)
    name = encode_function_name(name)

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
      vars = encode_vars(variant.bindings, context, "\n")
      body = encode_expressions(variant.body, context, opts, "\n")

      acc
      |> Formatter.maybe_append_new_line(
        "#{statement} (Hologram.patternMatchFunctionArgs(#{params}, arguments)) {"
      )
      |> Formatter.maybe_append_new_line(vars)
      |> Formatter.maybe_append_new_line(body)
      |> Formatter.maybe_append_new_line("}")
    end)
  end

  defp generate_params(variant, context) do
    Enum.map(variant.params, &Generator.generate(&1, context, %Opts{placeholder: true}))
    |> Enum.join(", ")
    |> wrap_with_array()
  end
end
