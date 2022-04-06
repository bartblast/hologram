# TODO: test

alias Hologram.Compiler.IR.RelaxedBooleanNotOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: RelaxedBooleanNotOperator do
  def aggregate(%{value: value}) do
    ModuleDefAggregator.aggregate(value)
  end
end
