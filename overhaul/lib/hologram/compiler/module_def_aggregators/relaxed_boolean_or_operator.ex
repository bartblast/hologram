# TODO: test

alias Hologram.Compiler.IR.RelaxedBooleanOrOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: RelaxedBooleanOrOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
