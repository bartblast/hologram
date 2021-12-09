alias Hologram.Compiler.ModuleDefAggregator
alias Hologram.Utils

defimpl ModuleDefAggregator, for: List do
  def aggregate(list) do
    Enum.map(list, &Task.async(fn -> ModuleDefAggregator.aggregate(&1) end))
    |> Utils.await_tasks()
  end
end
