# TODO: test

alias Hologram.Compiler.IR.UnaryNegativeOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: UnaryNegativeOperator do
  def aggregate(%{value: value}) do
    ModuleDefAggregator.aggregate(value)
  end
end
