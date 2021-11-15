alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.BooleanAndOperator

defimpl Aggregator, for: BooleanAndOperator do
  def aggregate(%{left: left, right: right}, module_defs) do
    module_defs = Aggregator.aggregate(left, module_defs)
    Aggregator.aggregate(right, module_defs)
  end
end
