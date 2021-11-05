alias Hologram.Compiler.Aggregator

defimpl Aggregator, for: Map do
  def aggregate(map, module_defs) do
    map
    |> Map.to_list()
    |> Aggregator.aggregate(module_defs)
  end
end
