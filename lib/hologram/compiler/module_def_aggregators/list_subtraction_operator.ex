# TODO: test

alias Hologram.Compiler.IR.ListSubtractionOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: ListSubtractionOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
