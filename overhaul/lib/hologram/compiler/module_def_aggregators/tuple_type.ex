alias Hologram.Compiler.IR.TupleType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: TupleType do
  def aggregate(%{data: data}) do
    ModuleDefAggregator.aggregate(data)
  end
end
