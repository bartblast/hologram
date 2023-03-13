# TODO: test

alias Hologram.Compiler.IR.StructType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: StructType do
  def aggregate(%{data: data}) do
    ModuleDefAggregator.aggregate(data)
  end
end
