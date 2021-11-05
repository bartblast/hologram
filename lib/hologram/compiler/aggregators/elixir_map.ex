alias Hologram.Compiler.Aggregator

defimpl Aggregator, for: Map do
  def aggregate(map, module_defs) do
    Map.to_list(map)
    |> Aggregator.aggregate(module_defs)
  end
end
