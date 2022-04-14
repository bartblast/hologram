# TODO: test

alias Hologram.Compiler.IR.NotEqualToOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: NotEqualToOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
