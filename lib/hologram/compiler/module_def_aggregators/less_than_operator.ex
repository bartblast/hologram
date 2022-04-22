# TODO: test

alias Hologram.Compiler.IR.LessThanOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: LessThanOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
