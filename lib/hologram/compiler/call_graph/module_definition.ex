alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.ModuleDefinition

defimpl CallGraph, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, call_graph, module_defs, _) do
    call_graph =
      if module_defs[module].page? do
        Graph.add_edge(call_graph, module, module.layout())
      else
        Graph.add_vertex(call_graph, module)
      end

    CallGraph.build(functions, call_graph, module_defs, module)
  end
end
