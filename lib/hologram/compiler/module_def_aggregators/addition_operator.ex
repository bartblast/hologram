# TODO: test

alias Hologram.Compiler.IR.AdditionOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: AdditionOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
