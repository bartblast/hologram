alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: List do
  def aggregate(list) do
    Enum.each(list, &ModuleDefAggregator.aggregate/1)
  end
end
