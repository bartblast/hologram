alias Hologram.Compiler.IR.ListIndexAccess
alias Hologram.Compiler.IR.ListType
alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: ListType do
  def deconstruct(%{data: data}, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      acc ++ PatternDeconstructor.deconstruct(value, path ++ [%ListIndexAccess{index: index}])
    end)
  end
end
