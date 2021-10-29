alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.IfExpression

defimpl Aggregator, for: IfExpression do
  def aggregate(%{condition: condition, do: do_clause, else: else_clause}, module_defs) do
    module_defs = Aggregator.aggregate(condition, module_defs)
    module_defs = Aggregator.aggregate(do_clause, module_defs)
    Aggregator.aggregate(else_clause, module_defs)
  end
end
