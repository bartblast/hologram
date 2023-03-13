# TODO: test

alias Hologram.Compiler.IR.UnaryPositiveOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: UnaryPositiveOperator do
  def aggregate(%{value: value}) do
    ModuleDefAggregator.aggregate(value)
  end
end
