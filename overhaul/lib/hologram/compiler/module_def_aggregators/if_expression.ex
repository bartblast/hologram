alias Hologram.Compiler.IR.IfExpression
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: IfExpression do
  def aggregate(%{condition: condition, do: do_clause, else: else_clause}) do
    ModuleDefAggregator.aggregate(condition)
    ModuleDefAggregator.aggregate(do_clause)
    ModuleDefAggregator.aggregate(else_clause)
  end
end
