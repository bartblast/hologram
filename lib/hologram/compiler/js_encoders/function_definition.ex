alias Hologram.Compiler.{Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.FunctionDefinitionVariants

defimpl JSEncoder, for: FunctionDefinitionVariants do
  use Hologram.Commons.Encoder

  def encode(%{name: name, variants: variants}, %Context{} = context, %Opts{} = opts) do
    body = encode_function_body(variants, context, opts)
    name = encode_identifier(name)

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
      vars = encode_vars(variant.bindings, context, opts)
      body = JSEncoder.encode(variant.body, context, opts)

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
    Enum.map(variant.params, &JSEncoder.encode(&1, context, %Opts{placeholder: true}))
    |> Enum.join(", ")
    |> wrap_with_array()
  end
end
