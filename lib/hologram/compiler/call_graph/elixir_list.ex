alias Hologram.Compiler.CallGraph

defimpl CallGraph, for: List do
  def build(list, call_graph, module_defs, from_vertex) do
    fun = &CallGraph.build(&1, &2, module_defs, from_vertex)
    Enum.reduce(list, call_graph, fun)
  end
end
