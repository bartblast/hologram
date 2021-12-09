alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: List do
  def build(list, call_graph, module_defs, from_vertex) do
    fun = &CallGraphBuilder.build(&1, &2, module_defs, from_vertex)
    Enum.reduce(list, call_graph, fun)
  end
end
