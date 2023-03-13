# TODO: test

alias Hologram.Compiler.IR.ConsOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: ConsOperator do
  def aggregate(%{head: head, tail: tail}) do
    ModuleDefAggregator.aggregate(head)
    ModuleDefAggregator.aggregate(tail)
  end
end
