# TODO: test

alias Hologram.Compiler.IR.MapType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: MapType do
  def aggregate(%{data: data}) do
    ModuleDefAggregator.aggregate(data)
  end
end
