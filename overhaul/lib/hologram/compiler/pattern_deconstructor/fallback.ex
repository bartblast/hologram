alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: Any do
  def deconstruct(_, _), do: []
end
