# TODO: test

alias Hologram.Compiler.IR.DotOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: DotOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
