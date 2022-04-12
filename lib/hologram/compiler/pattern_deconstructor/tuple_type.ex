alias Hologram.Compiler.IR.TupleAccess
alias Hologram.Compiler.IR.TupleType
alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: TupleType do
  def deconstruct(%{data: data}, path) do
    data
    |> Enum.with_index()
    |> Enum.reduce([], fn {value, index}, acc ->
      acc ++ PatternDeconstructor.deconstruct(value, path ++ [%TupleAccess{index: index}])
    end)
  end
end
