alias Hologram.Compiler.{Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.{CaseExpression, VariableAccess}

defimpl JSEncoder, for: CaseExpression do
  import Hologram.Commons.Encoder, only: [encode_expressions: 4]

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
    Elixir_Kernel_SpecialForms.case(#{condition_value}, function($condition) {
    #{anon_fun_body}
    })\
    """
  end

  defp encode_clauses(clauses, context, opts) do
    Enum.reduce(clauses, "", fn clause, acc ->
      statement = if acc == "", do: "if", else: "else if"
      clause_pattern = JSEncoder.encode(clause.pattern, context, %Opts{placeholder: true})
      vars = encode_vars(clause.bindings, context, opts)
      body = encode_expressions(clause.body, context, opts, "\n")

      acc
      |> Formatter.maybe_append_new_line(
        "#{statement} (Hologram.isCaseClausePatternMatched(#{clause_pattern}, $condition)) {"
      )
      |> Formatter.maybe_append_new_line(vars)
      |> Formatter.maybe_append_new_line(body)
      |> Formatter.maybe_append_new_line("}")
    end)
    |> String.trim_leading()
  end

  defp encode_vars(bindings, context, opts) do
    bindings
    |> Enum.map(&%{&1 | access_path: [%VariableAccess{name: "$condition"} | &1.access_path]})
    |> Hologram.Commons.Encoder.encode_vars(context, opts)
  end
end
