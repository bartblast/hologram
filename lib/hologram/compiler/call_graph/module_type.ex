alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.ModuleType

defimpl CallGraph, for: ModuleType do
  def build(%{module: module}, call_graph, _, from_vertex) do
    to_vertex = module
    Graph.add_edge(call_graph, from_vertex, to_vertex)
  end
end
