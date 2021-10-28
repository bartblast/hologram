alias Hologram.Compiler.Traverser

defimpl Traverser, for: List do
  def traverse(nodes, acc, from_vertex) do
    Enum.reduce(nodes, acc, &Traverser.traverse(&1, &2, from_vertex))
  end
end
