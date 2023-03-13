# TODO: test

alias Hologram.Compiler.IR.RelaxedBooleanAndOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: RelaxedBooleanAndOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
