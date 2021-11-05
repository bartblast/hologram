alias Hologram.Compiler.Aggregator

defimpl Aggregator, for: Tuple do
  def aggregate(tuple, module_defs) do
    Tuple.to_list(tuple)
    |> Aggregator.aggregate(module_defs)
  end
end
