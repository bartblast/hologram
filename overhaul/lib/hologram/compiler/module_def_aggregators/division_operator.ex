# TODO: test

alias Hologram.Compiler.IR.DivisionOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: DivisionOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
