alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: Map do
  def aggregate(map) do
    map
    |> Map.to_list()
    |> IRAggregator.aggregate()
  end
end
