alias Hologram.Compiler.Aggregator

defimpl Aggregator, for: Tuple do
  def aggregate(tuple, module_defs) do
    tuple
    |> Tuple.to_list()
    |> Aggregator.aggregate(module_defs)
  end
end
