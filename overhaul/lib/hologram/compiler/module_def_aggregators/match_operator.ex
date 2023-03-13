# TODO: test

alias Hologram.Compiler.IR.MatchOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: MatchOperator do
  def aggregate(%{right: right}) do
    ModuleDefAggregator.aggregate(right)
  end
end
