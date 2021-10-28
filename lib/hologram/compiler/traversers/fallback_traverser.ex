alias Hologram.Compiler.Traverser

defimpl Traverser, for: Any do
  def traverse(_, acc, _), do: acc
end
