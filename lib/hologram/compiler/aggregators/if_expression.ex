alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.IfExpression

defimpl Aggregator, for: IfExpression do
  def aggregate(%{condition: condition, do: do_clause, else: else_clause}, module_defs) do
    module_defs
    |> aggregate_from_condition(condition)
    |> aggregate_from_do_clause(do_clause)
    |> aggregate_from_else_clause(else_clause)
  end

  defp aggregate_from_condition(module_defs, condition) do
    Aggregator.aggregate(condition, module_defs)
  end

  defp aggregate_from_do_clause(module_defs, do_clause) do
    Aggregator.aggregate(do_clause, module_defs)
  end

  defp aggregate_from_else_clause(module_defs, else_clause) do
    Aggregator.aggregate(else_clause, module_defs)
  end
end
