alias Hologram.Compiler.IR.MapAccess
alias Hologram.Compiler.IR.MapType
alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: MapType do
  def deconstruct(%{data: data}, path) do
    Enum.reduce(data, [], fn {key, value}, acc ->
      acc ++ PatternDeconstructor.deconstruct(value, path ++ [%MapAccess{key: key}])
    end)
  end
end
