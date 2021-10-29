alias Hologram.Compiler.Aggregator

defimpl Aggregator, for: List do
  def aggregate(list, module_defs) do
    Enum.reduce(list, module_defs, &Aggregator.aggregate/2)
  end
end
