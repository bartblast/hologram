# TODO: test

alias Hologram.Compiler.IR.ListConcatenationOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: ListConcatenationOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
