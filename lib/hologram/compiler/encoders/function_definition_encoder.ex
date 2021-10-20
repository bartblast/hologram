alias Hologram.Compiler.{Context, Encoder, Formatter, Opts}
alias Hologram.Compiler.IR.FunctionDefinitionVariants

defimpl Encoder, for: FunctionDefinitionVariants do
  use Hologram.Compiler.Encoder.Commons

  def encode(%{name: name, variants: variants}, %Context{} = context, %Opts{} = opts) do
    body = encode_function_body(variants, context, opts)
    name = encode_function_name(name)

    "static #{name}() {#{body}"
    |> Formatter.maybe_append_new_line("}")
    |> Formatter.append_line_break()
  end

  defp encode_function_body(variants, context, opts) do
    invalid_case = encode_function_body_invalid_case()

    encode_function_body_valid_cases(variants, context, opts)
    |> Formatter.maybe_append_new_line(invalid_case)
  end

  defp encode_function_body_invalid_case do
    """
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }\
    """
  end

  defp encode_function_body_valid_cases(variants, context, opts) do
    Enum.reduce(variants, "", fn variant, acc ->
      statement = if acc == "", do: "if", else: "else if"
      params = encode_function_params(variant, context)
      vars = encode_vars(variant.bindings, context, "\n")
      body = encode_expressions(variant.body, context, opts, "\n")

      acc
      |> Formatter.maybe_append_new_line(
        "#{statement} (Hologram.isFunctionArgsPatternMatched(#{params}, arguments)) {"
      )
      |> Formatter.maybe_append_new_line(vars)
      |> Formatter.maybe_append_new_line(body)
      |> Formatter.maybe_append_new_line("}")
    end)
  end

  defp encode_function_params(variant, context) do
    Enum.map(variant.params, &Encoder.encode(&1, context, %Opts{placeholder: true}))
    |> Enum.join(", ")
    |> wrap_with_array()
  end
end
