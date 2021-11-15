alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.MatchOperator

defimpl Aggregator, for: MatchOperator do
  def aggregate(%{right: right}, module_defs) do
    Aggregator.aggregate(right, module_defs)
  end
end
