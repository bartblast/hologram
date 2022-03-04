alias Hologram.Compiler.IR.CaseExpression
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: CaseExpression do
  def aggregate(%{condition: condition, clauses: clauses}) do
    ModuleDefAggregator.aggregate(condition)
    Enum.map(clauses, &ModuleDefAggregator.aggregate(&1.body))
  end
end
