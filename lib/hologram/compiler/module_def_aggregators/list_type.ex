# TODO: test

alias Hologram.Compiler.IR.ListType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: ListType do
  def aggregate(%{data: data}) do
    ModuleDefAggregator.aggregate(data)
  end
end
