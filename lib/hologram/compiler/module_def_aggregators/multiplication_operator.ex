# TODO: test

alias Hologram.Compiler.IR.MultiplicationOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: MultiplicationOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
