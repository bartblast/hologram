alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: Map do
  def aggregate(map) do
    map
    |> Map.to_list()
    |> ModuleDefAggregator.aggregate()
  end
end
