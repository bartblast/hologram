alias Hologram.Compiler.IR.ModuleType
alias Hologram.Compiler.Traverser

defimpl Traverser, for: ModuleType do
  import Hologram.Compiler.Traverser.Commons

  def traverse(%{module: module}, {map, graph}, from_vertex) do
    map = maybe_add_module_def(map, module)

    graph =
      if from_vertex do
        Graph.add_edge(graph, from_vertex, module)
      else
        graph
      end

    {map, graph}
  end
end
