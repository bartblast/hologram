alias Hologram.Compiler.IRAggregator
alias Hologram.Utils

defimpl IRAggregator, for: List do
  def aggregate(list) do
    Enum.map(list, &Task.async(fn -> IRAggregator.aggregate(&1) end))
    |> Utils.await_tasks()
  end
end
