# TODO: test

alias Hologram.Compiler.IR.EqualToOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: EqualToOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
