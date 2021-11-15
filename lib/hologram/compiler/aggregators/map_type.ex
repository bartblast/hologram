alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.MapType

defimpl Aggregator, for: MapType do
  def aggregate(%{data: data}, module_defs) do
    Aggregator.aggregate(data, module_defs)
  end
end
