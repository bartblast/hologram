alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: Tuple do
  def aggregate(tuple) do
    tuple
    |> Tuple.to_list()
    |> IRAggregator.aggregate()
  end
end
