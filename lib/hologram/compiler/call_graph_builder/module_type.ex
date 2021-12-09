alias Hologram.Compiler.{CallGraphBuilder, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl CallGraphBuilder, for: ModuleType do
  def build(%{module: module}, call_graph, module_defs, from_vertex) do
    if Reflection.standard_lib?(module) do
      call_graph
    else
      CallGraphBuilder.build(module_defs[module], call_graph, module_defs)
      |> Graph.add_edge(from_vertex, module)
    end
  end
end
