alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: Tuple do
  def aggregate(tuple) do
    tuple
    |> Tuple.to_list()
    |> ModuleDefAggregator.aggregate()
  end
end
