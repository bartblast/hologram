# TODO: test

alias Hologram.Compiler.IR.BooleanAndOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: BooleanAndOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
