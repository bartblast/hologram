alias Hologram.Compiler.{Config, Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.CaseExpression

defimpl JSEncoder, for: CaseExpression do
  import Hologram.Commons.Encoder, only: [encode_vars: 3]

  @case_condition_js Config.case_condition_js()

  def encode(%{condition: condition, clauses: clauses}, %Context{} = context, %Opts{} = opts) do
    fallback_clause = """
    else {
    throw 'No case clause matching'
    }\
    """

    condition_value = JSEncoder.encode(condition, context, %Opts{})

    anon_fun_body =
      encode_clauses(clauses, context, opts)
      |> Formatter.maybe_append_new_line(fallback_clause)

    """
    Hologram.caseExpression(#{condition_value}, (#{@case_condition_js}) => {
    #{anon_fun_body}
    })\
    """
  end

  defp encode_clauses(clauses, context, opts) do
    Enum.reduce(clauses, "", fn clause, acc ->
      statement = if acc == "", do: "if", else: "else if"
      clause_pattern = JSEncoder.encode(clause.pattern, context, %Opts{placeholder: true})
      vars = encode_vars(clause.bindings, context, opts)
      body = JSEncoder.encode(clause.body, context, opts)

      acc
      |> Formatter.maybe_append_new_line(
        "#{statement} (Hologram.isPatternMatched(#{clause_pattern}, #{@case_condition_js})) {"
      )
      |> Formatter.maybe_append_new_line(vars)
      |> Formatter.maybe_append_new_line(body)
      |> Formatter.maybe_append_new_line("}")
    end)
    |> String.trim_leading()
  end
end
