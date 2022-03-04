alias Hologram.Compiler.{Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.CaseExpression

defimpl JSEncoder, for: CaseExpression do
  import Hologram.Commons.Encoder, only: [encode_expressions: 4, encode_var_value: 3]

  def encode(%{condition: condition, clauses: clauses}, %Context{} = context, %Opts{} = opts) do
    fallback_clause = """
    else {
    throw 'No case clause matching'
    }\
    """

    anon_fun_body =
      encode_clauses(condition, clauses, context, opts)
      |> Formatter.maybe_append_new_line(fallback_clause)

    "Elixir_Kernel_SpecialForms.case(function() { #{anon_fun_body} })"
  end

  defp encode_clauses(condition, clauses, context, opts) do
    condition_pattern = JSEncoder.encode(condition, context, %Opts{placeholder: true})
    condition_value = JSEncoder.encode(condition, context, %Opts{})

    Enum.reduce(clauses, "", fn clause, acc ->
      statement = if acc == "", do: "if", else: "else if"
      clause_pattern = JSEncoder.encode(clause.pattern, context, %Opts{placeholder: true})
      vars = encode_vars(clause.bindings, condition_value, context)
      body = encode_expressions(clause.body, context, opts, "\n")

      acc
      |> Formatter.maybe_append_new_line(
        "#{statement} (Hologram.isCaseClausePatternMatched(#{clause_pattern}, #{condition_pattern})) {"
      )
      |> Formatter.maybe_append_new_line(vars)
      |> Formatter.maybe_append_new_line(body)
      |> Formatter.maybe_append_new_line("}")
    end)
    |> String.trim_leading()
  end

  defp encode_var({name, path}, condition, context) do
    "let #{name} = #{condition}"
    |> encode_var_value(path, context)
    |> Formatter.append(";")
  end

  defp encode_vars(bindings, condition, context) do
    Enum.map(bindings, &encode_var(&1, condition, context))
    |> Enum.join("\n")
  end
end
